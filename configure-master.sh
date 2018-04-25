#!/bin/bash

k8sVersion=v1.10.0
k8sPodNetworkCidr=192.168.0.0/16
k8sServiceCidr=172.16.1.0/24
tokenTTL="24h0m0s"

set -o errexit
set -o pipefail


function usage() {
    echo "Usage: -m masterIp [-t tokenTTL] [-p podNetwork] [-s serviceNetwork] [-k k8sVersion]"
    echo
    echo "Options:"
    echo "    -m, --master-ip        Required: The external IP address of the master node"
    echo "    -t, --token-ttl        Optional: The duration before the bootstrap token is automatically deleted. If set to '0', the token will never expire. (default ${tokenTTL})"
    echo "    -p, --pod-network      Optional: Cluster wide IP subnet to use. (default ${k8sPodNetworkCidr})"
    echo "    -s, --service-network  Optional: A CIDR notation IP range from which k8s assigns service cluster IPs. This should be the same as the one provided for kube-apiserver \"-service-cluster-ip-range\" option. (default ${k8sServiceCidr})"
    echo "    -k, --k8s-version      Optional: Kubernetes version to pass to kubeadm.  (default ${k8sVersion})"
    echo "    -j, --kubeadm-token    Optional: Token used by kubeadm to allow other nodes to join"
    echo "    -h, --help             display help"
    exit 1
}

function validateArgs() {
    if [ -z "${k8sVersion}" ] || [ -z "${k8sPodNetworkCidr}" ] || [ -z "${k8sServiceCidr}" ] || [ -z "${tokenTTL}" ]; then
        echo "Invalid arguments - flag with missing argument value";
        usage;
    fi

    if [ -z "${masterIp}" ]; then
        echo "Missing required parameter masterIp\n Usage 'configure-master.sh masterIp'\n ex; ./configure-master.sh 10.142.0.2 ";
        usage;
    fi
}

if [ $# -lt 2 ]; then
    echo "Missing required parameter masterIp";
    usage
fi

#consume arguments
while true; do
  case "$1" in
    -m | --master-ip        ) masterIp="$2"; shift ;;
    -t | --token-ttl        ) tokenTTL="$2"; shift ;;
    -p | --pod-network      ) k8sPodNetworkCidr="$2"; shift ;;
    -s | --service-network  ) k8sServiceCidr="$2"; shift ;;
    -k | --k8s-version      ) k8sVersion="$2"; shift ;;
    -j | --kubeadm-token    ) kubeadmToken="$2"; shift ;;
    -h |--help ) usage;;
    -- ) shift; break ;;
        -*) echo "ERROR: unrecognized option $1"; exit 1;;
    * ) break ;;
  esac
  shift
done

validateArgs


#Sets up ovn northbound and southbound ports
ovn-nbctl set-connection ptcp:6641
ovn-sbctl set-connection ptcp:6642

swapoff -a
#init the master node
#Take note of the kubeadm output, specifically the join line, which will be needed to join your worker nodes to the cluster.
if [ -z "${kubeadmToken}" ]; then 
	kubeadm init --kubernetes-version ${k8sVersion} --apiserver-advertise-address ${masterIp} --pod-network-cidr ${k8sPodNetworkCidr} --service-cidr ${k8sServiceCidr} --token-ttl ${tokenTTL}
else 
	kubeadm init --kubernetes-version ${k8sVersion} --apiserver-advertise-address ${masterIp} --pod-network-cidr ${k8sPodNetworkCidr} --service-cidr ${k8sServiceCidr} --token-ttl ${tokenTTL} --token ${kubeadmToken}
fi

#This will setup kubectl to talk with the cluster
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -au):$(id -g) $HOME/.kube/config

#We don't need kube-proxy with the ovs/ovn setup, so delete the daemon set
kubectl delete ds kube-proxy -n kube-system

#This sets up rbac for ovn-kubernetes
cat > /opt/ovn-kubernetes-rbac.yaml <<- END
---
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
END

kubectl create -f /opt/ovn-kubernetes-rbac.yaml

#Retrieve the token ovn-kubernetes will use to communicate with the cluster
token=$(kubectl get secrets -n kube-system $(kubectl get secrets -n kube-system | grep ovn-controller-token | cut -f1 -d ' ') -o yaml | grep token: | cut -f2 -d":" | tr -d ' ' | tr -d '\t' | base64 -d)

echo ${token} > /vagrant/token

apiServer=https://${masterIp}:6443
hostname=$(hostname)

#create the ovnkube service file
cat > /etc/systemd/system/ovnkube.service <<- END
[Unit]
Description=ovnkube
Documentation=http://kubernetes.io/docs/

[Service]
ExecStart=/usr/bin/ovnkube -init-master ${hostname} \
                           -k8s-cacert /etc/kubernetes/pki/ca.crt \
                           -k8s-token "${token}" \
                           -nodeport \
                           -k8s-apiserver "${apiServer}" \
                           -cluster-subnet "${k8sPodNetworkCidr}" \
                           -service-cluster-ip-range "${k8sServiceCidr}" \
                           -net-controller \
                           -nb-address "tcp://${masterIp}:6641" \
                           -sb-address "tcp://${masterIp}:6642" \
                           -loglevel 5 \
                           -logfile /var/log/ovnkube.log

Restart=always
StartLimitInterval=0
RestartSec=10

[Install]
WantedBy=multi-user.target
END

#enable and start the service
systemctl enable ovnkube.service
systemctl start ovnkube.service

echo "Token: ${token}";
echo "Configuration complete.  Make sure to save the 'kubeadm join' command that was output.  It will be required to join workers to your cluster.";
