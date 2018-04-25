$hosts_script = <<SCRIPT

sudo -- sh -c -e cat > /etc/hosts <<- END
127.0.0.1 localhost
172.20.2.30 master
172.20.2.31 worker
172.20.2.32 windows
END

SCRIPT
Vagrant.configure("2") do |config|
    #installer
    config.vm.define "master" do |linux|
        linux.vm.box = 'bento/ubuntu-16.04'
        linux.vm.hostname = 'master'
        linux.vm.network 'private_network', ip: '172.20.2.30', auto_config: true
        linux.vm.provider :virtualbox do |vb|
            vb.name = 'master'
            vb.memory = 1024
        end
        linux.vm.provision "shell", inline: $hosts_script
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
        end
        linux.vm.provision "shell", inline: $hosts_script
    end
    #master
    config.vm.define "windows" do |windows|
        windows.vm.box = "gusztavvargadr/w16s"
        windows.vm.provider :virtualbox do |vb|
        windows.vm.network 'private_network', ip: '172.20.2.32', auto_config: true
            vb.name = 'windows'
            vb.memory = 4096
        end
    end   
    config.vm.provider "virtualbox" do |v|
      v.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
      v.customize ["modifyvm", :id, "--natdnsproxy1", "on"]
    end
end
