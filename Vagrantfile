# libvirt docs: https://vagrant-libvirt.github.io/vagrant-libvirt/configuration.html
Vagrant.configure("2") do |config|
  config.vm.box = "generic/ubuntu2204"

  # Control-plane
  config.vm.define "cp1" do |cp|
    cp.vm.hostname = "cp1"
    cp.vm.network "private_network", ip: "192.168.122.10"

    cp.vm.provider :libvirt do |lv|
      lv.cpus = 8
      lv.memory = 16384
      # lv.machine_virtual_size = 160 # GB
      lv.machine_type = "q35"
    end

    # Extend disk size and resize filesystem
    cp.vm.provision "shell", inline: <<-SHELL
      set -euo pipefail
      lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv
      resize2fs /dev/ubuntu-vg/ubuntu-lv
    SHELL
  end

  # Worker
  config.vm.define "worker1" do |wk|
    wk.vm.hostname = "worker1"
    wk.vm.network "private_network", ip: "192.168.122.11"

    wk.vm.provider :libvirt do |lv|
      lv.cpus = 4
      lv.memory = 8192
      # lv.machine_virtual_size = 160 # GB
      lv.machine_type = "q35"
    end

    # Extend disk size and resize filesystem
    wk.vm.provision "shell", inline: <<-SHELL
      set -euo pipefail
      lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv
      resize2fs /dev/ubuntu-vg/ubuntu-lv
    SHELL
  end
end
