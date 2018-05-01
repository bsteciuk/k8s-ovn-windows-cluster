ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa

echo "deb http://ppa.launchpad.net/ansible/ansible/ubuntu trusty main" | sudo tee -a /etc/apt/sources.list
sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 93C4A3FD7BB9C367
sudo apt-get update

sudo apt-get install python-pip ansible sshpass nginx -y
sudo cp /vagrant/ovs_debs.tar.gz /var/www/html
sshpass -p vagrant ssh-copy-id -o StrictHostKeyChecking=no vagrant@master
sshpass -p vagrant ssh-copy-id -o StrictHostKeyChecking=no vagrant@worker

git clone https://github.com/bsteciuk/ovn-kubernetes
pip install xmltodict pywinrm jmespath
cd ovn-kubernetes
git fetch origin ansible
git checkout ansible
cd contrib
echo "ovs_install_prebuilt_packages: true" >> inventory/group_vars/all
echo "ovs_install_prebuilt_packages: true" >> inventory/group_vars/kube-master
echo "ovs_install_prebuilt_packages: true" >> inventory/group_vars/kube-minion
sed -i -e 's/  debs_targz_link: "replace_me"/  debs_targz_link: "http:\/\/172.20.2.20\/ovs_debs.tar.gz"/g' roles/linux/openvswitch/vars/ubuntu.yml

ansible -m setup all
echo $?
#ansible-playbook ovn-kubernetes-cluster.yml
