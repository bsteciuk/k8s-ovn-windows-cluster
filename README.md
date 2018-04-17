

# NOTE: This document is still a work in progress

This document describes, step-by-step, how to configure a Kubernetes cluster comprised of:
* One Linux (Ubuntu) machine acting as Kubernetes master node and OVN central database.
* One Linux (Ubuntu) machine acting as Kubernetes worker node and OVN gateway node.
* One Windows machine acting as Kubernetes worker node.

## Cluster deployment

### Linux nodes

_For both the master node, and the worker node, perform the following steps:_


Copy [init.sh](init.sh) to the node, make it executable, and execute it as an elevated user.

This will install and configure the following:
 * Docker
 * Open vSwitch
 * Kubernetes v1.10.0 (update k8sVersion var in script to change version)
 * ovn-kubernetes 

```bash
chmod +x init.sh
sudo ./init.sh
```

The nodes must then be rebooted before continuing to the next steps.

```bash
reboot
````

#### Master Node

**ATTENTION**:
* From now on, it's assumed you're logged-in as `root`.
* Pay attention to the environment variables below, particularly:
  * `LOCAL_IP` must be the public IP of this node
  
On the master node, run the following commands (be aware of environment variables being set/used):

```bash
K8S_VERSION=v1.10.0
K8S_POD_NETWORK_CIDR=192.168.0.0/16
K8S_SERVICE_CIDR=172.16.1.0/24
TOKEN_TTL=0

#Sets up ovn northbound and southbound ports
ovn-nbctl set-connection ptcp:6641
ovn-sbctl set-connection ptcp:6642

#init the master node
kubeadm init --kubernetes-version ${K8S_VERSION} --pod-network-cidr ${K8S_POD_NETWORK_CIDR} --service-cidr ${K8S_SERVICE_CIDR} --token-ttl ${TOKEN_TTL}

```

Take note of the kubeadm output, specifically the join line (example below), which will be needed to join your worker nodes to the cluster.
`#example kubeadm join output.  You will need your cluster-unique tokens as output by kubeadm
  kubeadm join 10.142.0.9:6443 --token mgeq2z.os1y2nqg5hxs3ga5 --discovery-token-ca-cert-hash sha256:585da15f1f977d1ac900e6aee1a646df1331efc2cfa1ea6e934f5ccc8829d608`

Run the following commands:

```bash
#This will setup kubectl to talk with the cluster

mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config


#This sets up rbac for ovn-kubernetes

 cat <<EOF | kubectl create -f -
 apiVersion: v1
 kind: ServiceAccount
 metadata:
   name: ovn-controller
   namespace: kube-system
 ---
 kind: ClusterRole
 apiVersion: rbac.authorization.k8s.io/v1beta1
 metadata:
   name: ovn-controller
 rules:
   - apiGroups:
       - ""
       - networking.k8s.io
     resources:
       - pods
       - services
       - endpoints
       - namespaces
       - networkpolicies
       - nodes
     verbs:
       - get
       - list
       - watch
   - apiGroups:
       - ""
     resources:
       - nodes
       - pods
     verbs:
       - patch
 ---
 kind: ClusterRoleBinding
 apiVersion: rbac.authorization.k8s.io/v1beta1
 metadata:
   name: ovn-controller
 roleRef:
   apiGroup: rbac.authorization.k8s.io
   kind: ClusterRole
   name: ovn-controller
 subjects:
 - kind: ServiceAccount
   name: ovn-controller
   namespace: kube-system
EOF


#Retrieve the token ovn-kubernetes will use to communicate with the cluster
TOKEN=$(kubectl get secrets -n kube-system $(kubectl get secrets -n kube-system | grep ovn-controller-token | cut -f1 -d ' ') -o yaml | grep token: | cut -f2 -d":" | tr -d ' ' | tr -d '\t' | base64 -d)
```

Make sure that the `MASTER_HOST` environment variable below is set correctly to your master nodes ip.

```bash
MASTER_HOST=10.142.0.9
APISERVER=https://${MASTER_HOST}:6443
HOSTNAME=$(hostname)



#create the ovnkube service file
cat > /etc/systemd/system/ovnkube.service <<- END
[Unit]
Description=ovnkube
Documentation=http://kubernetes.io/docs/

[Service]
ExecStart=/usr/bin/ovnkube -init-master ${HOSTNAME} \
                           -k8s-cacert /etc/kubernetes/pki/ca.crt \
                           -k8s-token "${TOKEN}" \
                           -nodeport \
                           -k8s-apiserver "${APISERVER}" \
                           -cluster-subnet "${K8S_POD_NETWORK_CIDR}" \
                           -service-cluster-ip-range "${K8S_SERVICE_CIDR}" \
                           -net-controller \
                           -nb-address "tcp://${MASTER_HOST}:6641" \
                           -sb-address "tcp://${MASTER_HOST}:6642" \
                           -loglevel 5 \
                           -logfile /var/log/ovnkube.log

Restart=always
StartLimitInterval=0
RestartSec=10

[Install]
WantedBy=multi-user.target
END

#and enable the service
systemctl enable ovnkube.service
systemctl start ovnkube.service
```



#### Worker node

On the worker node, we'll need to join the cluster using the kubeadm join command we saved from the master node, and create the ovnkube service which will act as the ovn gateway

Start with the kubeadm join command
```bash
#Example - use the one returned from 'kubeadm init' on your master node. 
# kubeadm join --token c4892a.5a8832696eebe8e6 10.142.0.10:6443 --discovery-token-ca-cert-hash sha256:0073fc242f11da7d775c25684ee3aeed0a4f002a14a2ac91709fb8f41884243e

```


```bash
K8S_VERSION=v1.10.0
K8S_POD_NETWORK_CIDR=192.168.0.0/16
K8S_SERVICE_CIDR=172.16.1.0/24
HOSTNAME=$(hostname)
TOKEN=<TOKEN_VALUE_FROM_MASTER> #example 'eyJhbGciOiJSUzI1NiIsImtpZCI6IiJ9.eyJpc3MiOiJrdWJlcm5ldGVzL3NlcnZpY2VhY2NvdW50Iiwia3ViZXJuZXRlcy5pby9zZXJ2aWNlYWNjb3VudC9uYW1lc3BhY2UiOiJrdWJlLXN5c3RlbSIsImt1YmVybmV0ZXMuaW8vc2VydmljZWFjY291bnQvc2VjcmV0Lm5hbWUiOiJvdm4tY29udHJvbGxlci10b2tlbi1iN3M0eiIsImt1YmVybmV0ZXMuaW8vc2VydmljZWFjY291bnQvc2VydmljZS1hY2NvdW50Lm5hbWUiOiJvdm4tY29udHJvbGxlciIsImt1YmVybmV0ZXMuaW8vc2VydmljZWFjY291bnQvc2VydmljZS1hY2NvdW50LnVpZCI6ImRlYmY5ODYwLTNkYWMtMTFlOC1hMGI0LTQyMDEwYThlMDAwOSIsInN1YiI6InN5c3RlbTpzZXJ2aWNlYWNjb3VudDprdWJlLXN5c3RlbTpvdm4tY29udHJvbGxlciJ9.KnWeyCSnOPQUz86GXNxbcIVL1ZS_NJPMEWYRd44L3TBhhxt0isKZisbvUM5bHSiv2cwX_2AjC8cI9wi_fsUOIIZPWueuYBSsK9bOMcV9zDzGlDfcNM7LQVdMetNWxcCOxGprxHTseIUczd7Z189vEin0kM4HfkmcGJrNCaA8XdSe_c50yhj0WNl--2mjduT1HWrMZuYf9KcAH1vqHMJXyQYbG66DshfMz-u8Y1mNwBNJ2FpCoMFqDoxknbFyHWHmRjR-HNwginKhfB_1c0EJD1LZKaJNQdwyp0PTJWEYLJA5yVWmjyb4fHZSGchE-eHBD_XZa88D0dqXCfIJj4Lomg'
MASTER_IP=<MASTER_IP> #Same used for ovnkube init-master 
INTERFACE_NAME=<WORKER_IP_INTERFACE_NAME> #example eth0 or ens4
GATEWAY_ADDRESS=<GATEWAY_ADDRESS_FOR_NODE> #example 10.142.0.1
```
  



```bash

#create the ovnkube service file

cat > /etc/systemd/system/ovnkube.service <<- END
[Unit]
Description=ovnkube
Documentation=http://kubernetes.io/docs/

[Service]
ExecStart=/usr/bin/ovnkube -init-node ${HOSTNAME} \
                           -k8s-cacert /etc/kubernetes/pki/ca.crt \
                           -k8s-token "${TOKEN}" \
                           -nodeport \
                           -init-gateways \
                           -k8s-apiserver "https://${MASTER_IP}:6443" \
                           -cluster-subnet "${K8S_POD_NETWORK_CIDR}" \
                           -service-cluster-ip-range "${K8S_SERVICE_CIDR}" \
                           -gateway-nexthop "${GATEWAY_ADDRESS}" \
                           -gateway-interface "${INTERFACE_NAME}" \
                           -nb-address "tcp://${MASTER_IP}:6641" \
                           -sb-address "tcp://${MASTER_IP}:6642" \
                           -loglevel 5 \
                           -logfile /var/log/ovnkube.log

Restart=always
StartLimitInterval=0
RestartSec=10

[Install]
WantedBy=multi-user.target
END

#and enable the service
systemctl enable ovnkube.service
systemctl start ovnkube.service

```

#### Windows node

First, copy [init.ps1](init.ps1) to the windows node and execute it as Administrator from a powershell window


*Note for Windows Server 2016 RTM (build number 14393)*
  * You will need to set the following environment variable
    `setx -m CONTAINER_NETWORK "external"`
  * Currently, kubelet.exe must be built from https://github.com/kubernetes/kubernetes/pull/61940


The node will need to be rebooted before we can continue.

Next, we need to install openvswitch.  In a powershell window running as Administrator, run the following:

```
cmd /c 'msiexec /i openvswitch-hyperv-installer-beta.msi ADDLOCAL="OpenvSwitchCLI,OpenvSwitchDriver,OVNHost" /qn'
```

You must close this powershell window and open a new session to ensure the required environment variables are set.
You can verify everything is ok by running `ovs-vsctl.exe --version`.  If you see version info displayed, you are all set. 


Copy the kubernetes binaries we need into C:\k, and create the kubelet service
```bash
mkdir C:\k
cp C:\kubeadm.exe C:\k
cp C:\kubelet.exe C:\k

cd C:\k
.\kubelet-service.exe install

```

Now we must join the windows node to the cluster with kubeadm.  Make sure to use the values returned from 'kubeadm init' on your master node.

```
kubeadm join --token bbf7cd.b3ad4b5ffdabb2aa 10.142.0.33:6443 --discovery-token-ca-cert-hash sha256:7fbaced425492d066ec463c85e8a7300e4e6f6349e865adfbc7761b00a1038cf
```
Make sure the kubelet service is started:
```
start-service kubelet
```

Now we need to run a command from the master to see what pod subnet this node has been assigned. You can determine this by running the following from the master:

(be sure swap out <WINDOWS_HOSTNAME> for the actual windows hostname)
```bash
kubectl describe node "<WINDOWS_HOSTNAME>" | grep ovn_host_subnet
```
The output should look something like: 
```bash
ovn_host_subnet=10.0.6.0/24

```
We will need ot use this value in the next step.




```bash

$GATEWAY="<GATEWAY_IP>" #The first IP in the ovn_host_subnet for this node ex. "10.0.6.1"
$SUBNET="<OVN_HOST_SUBNET>" #The ovn_host_subnet returned ex. "10.0.6.0/24"
$INTERFACE_ALIAS="<NETWORK_INTERFACE_ALIAS>" #example "Ethernet"

$configureScript=@"
docker network create -d transparent --gateway $GATEWAY --subnet $SUBNET -o com.docker.network.windowsshim.interface="Ethernet" external
sleep 2;
$a = Get-NetAdapter | where Name -Match HNSTransparent
Rename-NetAdapter $a[0].Name -NewName HNSTransparent
Stop-Service ovs-vswitchd -force; Disable-VMSwitchExtension "Cloudbase Open vSwitch Extension";
ovs-vsctl --no-wait del-br br-ex
ovs-vsctl --no-wait --may-exist add-br br-ex
ovs-vsctl --no-wait add-port br-ex HNSTransparent -- set interface HNSTransparent type=internal
ovs-vsctl --no-wait add-port br-ex '$INTERFACE_ALIAS'
Get-VMSwitch -SwitchType External | Enable-VMSwitchExtension "Cloudbase Open vSwitch Extension"; sleep 2; Restart-Service ovs-vswitchd
"@
$configureScript | Out-File 'C:\k\configure.ps1'

#Note, you may lose RDP connectivity temporarily when running this script
C:\k\configure.ps1

```

OVS needs a unique id for each node, we will generate and assign it with the following:

```bash

$GUID = (New-Guid).Guid
ovs-vsctl set Open_vSwitch . external_ids:system-id="$($GUID)"
```

Add an entry to the hosts file for this machine (swap in the appropriate values)

```
Add-Content C:\Windows\System32\drivers\etc\hosts "`r`n<IP_ADDRESS> <HOSTNAME>"
```

Lastly, we run ovnkube to complete the virtual network configuration

```bash
.\ovnkube.exe -k8s-apiserver https://<MASTER_IP>:6443 `
        -k8s-cacert "C:\etc\kubernetes\pki\ca.crt" `
        -init-node "<HOSTNAME>" `
        -k8s-token "<TOKEN>" `
        -nb-address "tcp://<MASTER_IP>:6641" `
        -sb-address "tcp://<MASTER_IP>:6642" `
        -cluster-subnet "<K8S_POD_NETWORK_CIDR>" `
        -cni-conf-dir "C:\cni-conf" `
        -service-cluster-ip-range "<K8S_SERVICE_CIDR>"
```