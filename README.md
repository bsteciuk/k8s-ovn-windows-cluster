

# NOTE: This document is still a work in progress

This document will walk you through, step-by-step, how to stand up a Kubernetes cluster comprised of:
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
 * Kubernetes v1.10.0 (update k8sVersion variable in init.sh script to change version)

```bash
chmod +x init.sh
sudo ./init.sh
```

The nodes must then be rebooted before continuing to the next steps.

```bash
reboot
````

#### Master Node

Copy [configure-master.sh](configure-master.sh) to the node, make it executable, and execute it as an elevated user.

This will: 
* Configure the ovn connection ports
* run `kubeadm init` to bring up the kubernetes control plane
* add ovn-kubernetes rbac 
* ovn-kubernetes service account, cluster role, and cluster role binding
* configure ovn-kubernetes as a service and start it

**We will need to take note of two lines of output from this script.**

The "kubeadm join" line, gives the kubeadm join command used to add other nodes to our cluster.  Example below:
```
kubeadm join 10.142.0.9:6443 --token mgeq2z.os1y2nqg5hxs3ga5 --discovery-token-ca-cert-hash sha256:585da15f1f977d1ac900e6aee1a646df1331efc2cfa1ea6e934f5ccc8829d608
```
The token line provides us with the token that ovn-kubernetes will use to authenticate against the api server.  Example below:
```
Token: eyJhbGciOiJSUzI1NiIsImtpZCI6IiJ9.eyJpc3MiOiJrdWJlcm5ldGVzL3NlcnZpY2VhY2NvdW50Iiwia3ViZXJuZXRlcy5pby9zZXJ2aWNlYWNjb3VudC9uYW1lc3BhY2UiOiJrdWJlLXN5c3RlbSIsImt1YmVybmV0ZXMuaW8vc2VydmljZWFjY291bnQvc2VjcmV0Lm5hbWUiOiJvdm4tY29udHJvbGxlci10b2tlbi1xamhjZyIsImt1YmVybmV0ZXMuaW8vc2VydmljZWFjY291bnQvc2VydmljZS1hY2NvdW50Lm5hbWUiOiJvdm4tY29udHJvbGxlciIsImt1YmVybmV0ZXMuaW8vc2VydmljZWFjY291bnQvc2VydmljZS1hY2NvdW50LnVpZCI6IjlmNTU3MjQ1LTQzMmEtMTFlOC1hNTExLTQyMDEwYThlMDAwOSIsInN1YiI6InN5c3RlbTpzZXJ2aWNlYWNjb3VudDprdWJlLXN5c3RlbTpvdm4tY29udHJvbGxlciJ9.bWjrRX452E6zCrTQ47sc1XnfFzr33sqojyI7v27Hnic7O7U4IPcwVYkeXkMfTw4ayeLdrwEA-pelE_Lj1G_HDeS3X8yrv1tzuZr_2v2caTzkEV_bXU0p6t4kjd62wJaUNEtA--9FlRSQOPtDrDJDjLkuTdb-QYVMkFX1TsuBPh_axLCiyC7xPEUh3S8cv5PlH1D9l0RO7Nsrl1eM2TGnYa3Vrl3xMCqOBokS0hXARm5iawQP8B7c56NuOgRZtsWYbIUBfviRsj4Om8jsSzy80JAHg2oaW5lqvPWYdK5ggVK4fCSBeR_V6mt-6Vgg7qlchz1TL-gD6l3rc7oHSHqxtw
```

```bash
chmod +x configure-master.sh
#run ./configure-master.sh -h for full set of arguments
sudo ./configure-master.sh -m <MASTER_IP>
```

#### Worker node

On the worker node, we'll need to join the cluster using the kubeadm join command we saved from the master node in the previous step.

```bash
#disable swap
swapoff -a 

#Example - use the command and values returned from 'kubeadm init' on your master node. 
kubeadm join --token c4892a.5a8832696eebe8e6 10.142.0.10:6443 --discovery-token-ca-cert-hash sha256:0073fc242f11da7d775c25684ee3aeed0a4f002a14a2ac91709fb8f41884243e

```

Next, Copy [configure-worker.sh](configure-worker.sh) to the node, make it executable, and execute it as an elevated user.

This will: 
* configure ovn-kubernetes as a service and start it


```bash
chmod +x configure-worker.sh
#run ./configure-worker.sh -h for full set of arguments
sudo ./configure-worker.sh -m <MASTER_IP> -t <TOKEN> -i ens4 -g <GATEWAY_IP> 
```

### Windows node

First, copy [init.ps1](init.ps1) to the windows node and execute it as Administrator from a powershell window.

This will:

* Install nuget and docker
* Download and configure kubelet service wrapper
* Download the Open vSwitch msi
* Download and extract the kubelet and kubeadm binaries to C:\k

*Note, you may lose RDP connectivity temporarily when running this script.*

**Notes for Windows Server 2016 RTM (build number 14393)**
  * You will need to set the following environment variable
    ```
    setx -m CONTAINER_NETWORK "external"
    ```
  * Currently, kubelet.exe must be built from https://github.com/kubernetes/kubernetes/pull/61940 until it merges.
  * There is a current limitation of one container per pod on Windows Server 2016 RTM


The node will need to be rebooted before we can continue.

Next, we need to install the Open vSwitch msi we downloaded.  In a powershell window running as Administrator, run the following:

```
cmd /c 'msiexec /i openvswitch-hyperv-installer-beta.msi ADDLOCAL="OpenvSwitchCLI,OpenvSwitchDriver,OVNHost" /qn'
```

You must close this powershell window and open a new session to ensure the required environment variables are set.
You can verify everything is ok by running `ovs-vsctl.exe --version`.  If you see version info displayed, you are all set. 


Next we need to create the kubelet service (note, if using kubelet built from the PR mentioned above, you will need to copy it to the node to C:\k\kubelet.exe)
If you wish to change any of the kubelet command line arguments, they can be set/added to C:\k\kubelet-service.xml
```bash
cd C:\k
.\kubelet-service.exe install

```

Now we must join the windows node to the cluster with kubeadm.  Make sure to use the values returned from 'kubeadm init' on your master node.

```
.\kubeadm join --token bbf7cd.b3ad4b5ffdabb2aa 10.142.0.33:6443 --discovery-token-ca-cert-hash sha256:7fbaced425492d066ec463c85e8a7300e4e6f6349e865adfbc7761b00a1038cf
```
Make sure the kubelet service is start
```
start-service kubelet
```

Next, we need to run a command from the master to see what pod subnet this node has been assigned. You can determine this by running the following from the master:

(be sure swap out <WINDOWS_HOSTNAME> for the actual windows hostname)
```bash
kubectl describe node "<WINDOWS_HOSTNAME>" | grep ovn_host_subnet
```
The output should look something like: 
```bash
ovn_host_subnet=10.0.6.0/24

```
We will need ot use this value in the next step.

Copy [configure-windows.ps1](configure-windows.ps1) to the windows node
This will: 
* Setup the external docker network
* Rename network adapters
* Some initial Open vSwitch configuration

Add an entry to the hosts file for this machine (swap in the appropriate values)

```
Add-Content C:\Windows\System32\drivers\etc\hosts "`r`n<IP_ADDRESS> <HOSTNAME>"
```

Copy [ovn_k8s.conf-windows](ovn_k8s.conf-windows) to `C:\`
The ovn-kubernetes windows binaries were built on your master (during init.sh).  You should find them at the following path on your master
```bash
/opt/ovn-kubernetes/go-controller/_output/go/windows/ovnkube.exe
/opt/ovn-kubernetes/go-controller/_output/go/windows/ovn-k8s-cni-overlay.exe

```

Copy both of these binaries to `C:\cni` on your windows node.

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