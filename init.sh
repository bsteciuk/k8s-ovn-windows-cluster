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


#Install prereqs
apt-get update
apt-get install -y docker.io golang-1.9-go python-six
ln -s /usr/lib/go-1.9/bin/go /usr/bin/go

sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates
echo "deb https://packages.wand.net.nz $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/wand.list
sudo curl https://packages.wand.net.nz/keyring.gpg -o /etc/apt/trusted.gpg.d/wand.gpg
sudo apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D
sudo su -c "echo \"deb https://apt.dockerproject.org/repo ubuntu-xenial main\" >> /etc/apt/sources.list.d/docker.list"
sudo apt-get update

#Install OVS and dependencies
sudo apt-get build-dep dkms -y
sudo apt-get install python-six openssl python-pip -y
sudo -H pip install --upgrade pip

sudo apt-get install openvswitch-datapath-dkms=2.8.1-1 -y
sudo apt-get install openvswitch-switch=2.8.1-1 openvswitch-common=2.8.1-1 libopenvswitch=2.8.1-1 -y
sudo -H pip install ovs

sudo apt-get install ovn-central=2.8.1-1 ovn-common=2.8.1-1 ovn-host=2.8.1-1 -y



#Set docker cgroupdriver
cat << EOF > /etc/docker/daemon.json
{
  "exec-opts": ["native.cgroupdriver=cgroupfs"]
}
EOF

echo vport_geneve >> /etc/modules-load.d/modules.conf

#Get kubernetes binaries
cd /tmp

wget https://dl.k8s.io/${k8sVersion}/kubernetes-server-linux-amd64.tar.gz
tar -xvzf kubernetes-server-linux-amd64.tar.gz -C /opt/

#Get CNI binaries
mkdir -p /opt/cni/bin
wget https://github.com/containernetworking/plugins/releases/download/v0.6.0/cni-plugins-amd64-v0.6.0.tgz
tar -xvzf cni-plugins-amd64-v0.6.0.tgz -C /opt/cni/bin


#Get, build, and install ovn-kubernetes
cd /opt
git clone https://github.com/openvswitch/ovn-kubernetes

cd ovn-kubernetes/go-controller
#We are switching to PR with fixes for windows RTM
git fetch origin pull/288/head:PR-288
git checkout PR-288
make all install
make windows

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
wget https://raw.githubusercontent.com/kubernetes/kubernetes/${k8sVersion}/build/debs/10-kubeadm.conf

systemctl enable kubelet

touch "${initTouchFile}"

echo "Initialization successful.  Please reboot the node."