$hosts_script = <<SCRIPT
sudo -- sh -c -e cat > /etc/hosts <<- END
127.0.0.1 localhost
172.20.2.30 master
172.20.2.31 worker
172.20.2.32 windows
END
SCRIPT

#Token to be used for kubeadm join.  Modify if desired. See https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-token/
kubeadm_token = "nlmuc8.goov2ohg5tfsvxja"

Vagrant.configure("2") do |config|
    #installer
    config.vm.define "master" do |linux|
        linux.vm.box = 'bento/ubuntu-16.04'
        linux.vm.hostname = 'master'
        linux.vm.network 'private_network', ip: '172.20.2.30', auto_config: true
        linux.vm.provider :virtualbox do |vb|
            vb.name = 'master'
            vb.memory = 1024
            vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
            vb.customize ["modifyvm", :id, "--natdnsproxy1", "on"]
            vb.customize ["modifyvm", :id, "--nictype1", "virtio"]
        end
        linux.vm.provision "shell", inline: $hosts_script
        linux.vm.provision "shell", path: "init.sh", privileged: true
        linux.vm.provision :reload
	linux.vm.provision "shell", path: "configure-master.sh", privileged: true, :args => "-m '172.20.2.30' -j #{kubeadm_token}"
        linux.vm.provision "shell", inline: "sudo kubeadm token create --print-join-command > /vagrant/join.sh && chmod +x /vagrant/join.sh"
        
    end
    #master
    config.vm.define "worker" do |linux|
        linux.vm.box = 'bento/ubuntu-16.04'
        linux.vm.hostname = 'worker'
        linux.vm.network 'private_network', ip: '172.20.2.31', auto_config: true
        linux.vm.provider :virtualbox do |vb|
            vb.name = 'worker'
            vb.memory = 2048
            vb.customize [
                'modifyvm', :id,
                '--nicpromisc3', "allow-all"
            ]
            vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
            vb.customize ["modifyvm", :id, "--natdnsproxy1", "on"]
            vb.customize ["modifyvm", :id, "--nictype1", "virtio"]
        end
        linux.vm.provision "shell", inline: $hosts_script
        linux.vm.provision "shell", path: "init.sh", privileged: true
	linux.vm.provision :reload
        linux.vm.provision "shell", path: "join.sh", privileged: true
        linux.vm.provision "shell", path: "configure-worker.sh", privileged: true, :args => "-t /vagrant/token -m 172.20.2.30 -i eth0 -g 10.0.2.2"
    end
    #master
    config.vm.define "windows" do |windows|
        windows.vm.box = "gusztavvargadr/w16s"
        windows.vm.network 'private_network', ip: '172.20.2.32', auto_config: true
        windows.vm.provider :virtualbox do |vb|
            vb.name = 'windows'
            vb.memory = 4096
        end
        windows.vm.provision "shell", path: "init.ps1", privileged: true
        windows.vm.provision "shell", inline: 'setx -m CONTAINER_NETWORK "external"', privileged: true
        windows.vm.provision :reload
    end
end
