#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

initTouchFile=/root/init.complete

#if touch file exists, bail, we've already run successfully
if [ -f "${initTouchFile}" ]; then
    exit 0
fi

k8sVersion=v1.10.0
# since ovn k8s doesn't publish actual versions, use the short git sha
ovnk8sVersion=413b854
# might need to change this URL to a more-official looking one
# maybe put this in an Apprenda-owned fork of the ovn-kubernetes repo
ovnk8sTarGz=ovn-kubernetes-rev-${ovnk8sVersion}.tar.gz
ovnk8sBinsUrl=https://github.com/akochnev/k8s-ovn-windows-cluster/releases/download/ovn-prebuilt-${ovnk8sVersion}/${ovnk8sTarGz}

#Install dependencies
apt-get update -q
apt-get upgrade -q -y

echo "deb https://packages.wand.net.nz $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/wand.list
sudo curl -s https://packages.wand.net.nz/keyring.gpg -o /etc/apt/trusted.gpg.d/wand.gpg
sudo apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D
sudo su -c "echo \"deb https://apt.dockerproject.org/repo ubuntu-xenial main\" >> /etc/apt/sources.list.d/docker.list"
sudo su -c "echo \"deb-src http://archive.ubuntu.com/ubuntu/ xenial main restricted\" >> /etc/apt/sources.list.d/dkms.list"

sudo apt-get update

apt-get install -y linux-headers-4.4.0-87-generic docker.io python-six apt-transport-https ca-certificates openssl \
 python-pip openvswitch-datapath-dkms=2.8.1-1 openvswitch-switch=2.8.1-1 openvswitch-common=2.8.1-1 \
 libopenvswitch=2.8.1-1 ovn-central=2.8.1-1 ovn-common=2.8.1-1 ovn-host=2.8.1-1

sudo apt-get build-dep dkms -y

cd /tmp
wget -q https://dl.google.com/go/go1.10.1.linux-amd64.tar.gz
tar -xvzf go1.10.1.linux-amd64.tar.gz -C /usr/local
export PATH=$PATH:/usr/local/go/bin
echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile

sudo -H pip install ovs

echo vport_geneve >> /etc/modules-load.d/modules.conf

#Set docker cgroupdriver
cat << EOF > /etc/docker/daemon.json
{
  "exec-opts": ["native.cgroupdriver=cgroupfs"]
}
EOF

#disable swap
sed -i '/ swap / s/^/#/' /etc/fstab

#Get kubernetes binaries and extract to /opt/kubernetes
cd /tmp
echo "Downloading K8s binaries... this may take a few minutes."
wget -q https://dl.k8s.io/${k8sVersion}/kubernetes-server-linux-amd64.tar.gz
tar -xvzf kubernetes-server-linux-amd64.tar.gz -C /opt/

#Get CNI binaries and extract to /opt/cni/bin
mkdir -p /opt/cni/bin
wget -q https://github.com/containernetworking/plugins/releases/download/v0.6.0/cni-plugins-amd64-v0.6.0.tgz
tar -xvzf cni-plugins-amd64-v0.6.0.tgz -C /opt/cni/bin


#Get OVN-k8s pre-built binaries
mkdir -p /opt/ovn-kubernetes
wget -q ${ovnk8sBinsUrl}
tar -xvzf ${ovnk8sTarGz} -C /opt/ovn-kubernetes
cp /opt/ovn-kubernetes/bin/ovnkube /usr/bin/
cp /opt/ovn-kubernetes/bin/ovn-k8s-overlay /opt/cni/bin/
cp /opt/ovn-kubernetes/bin/ovn-kube-util /usr/bin/
cp /opt/ovn-kubernetes/bin/ovn-k8s-cni-overlay /opt/cni/bin/


#copy the cni config
cat << EOF > /etc/openvswitch/ovn_k8s.conf
[default]
mtu=1500
conntrack-zone=64321

[kubernetes]
cacert=/etc/kubernetes/pki/ca.crt

[logging]
loglevel=5
logfile=/var/log/ovnkube.log

[cni]
conf-dir=/etc/cni/net.d
plugin=ovn-k8s-cni-overlay
EOF

#Get cni bins and copy ovn-k8s-cni-overlay in

mkdir -p /etc/cni/net.d/
echo '{"name":"ovn-kubernetes", "type":"ovn-k8s-cni-overlay"}' > /etc/cni/net.d/10-ovn-kubernetes.conf

#Copy k8s bins to /usr/bin
cp /opt/kubernetes/server/bin/kubelet /usr/bin
cp /opt/kubernetes/server/bin/kubectl /usr/bin
cp /opt/kubernetes/server/bin/kubeadm /usr/bin

#Create the kubelet service file
cat > /etc/systemd/system/kubelet.service <<- END
[Unit]
Description=kubelet: The Kubernetes Node Agent
Documentation=http://kubernetes.io/docs/

[Service]
ExecStart=/usr/bin/kubelet
Restart=always
StartLimitInterval=0
RestartSec=10

[Install]
WantedBy=multi-user.target
END

#Add the kubeadm drop-in file

mkdir -p /etc/systemd/system/kubelet.service.d
cd /etc/systemd/system/kubelet.service.d
wget -q https://raw.githubusercontent.com/kubernetes/kubernetes/${k8sVersion}/build/debs/10-kubeadm.conf

systemctl enable kubelet

touch "${initTouchFile}"

echo "Initialization successful.  Please reboot the node."
