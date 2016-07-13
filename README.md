# KPC
OpenStack Kolla on PXE-booted CoreOS

Get deployer node running on CoreOS that has been installed to disk.
Recommended procedure:  
  - Download the CoreOS ISO and copy to USB flash drive with 'dd' or one of the many generic ISO to USB helper tools (Rufus [highly recommended on Windows], UNetbootin, Universal USB Installer, etc.).
  - Set deployer node to boot from the disk you will install to, then perform a one-time boot from the flash drive; this will bring up a live-booted (to RAM) CoreOS system and automatically log you in as '**core**'.
  - Set a password for the **core** user:  
    ```
    sudo passwd core
    ```
  - Note the IP the system gets, as we will SSH to the host in next steps:  
    ```
    ip a
    ```
  - SSH to the host from your machine, logging in as **core** using the password you just set
  - Create a cloud-init or ignition config that sets an SSH key for **core** and sets Docker to use an insecure registry. We will pass this file to `coreos-install` to use while installing the OS to disk. The IP or hostname of the insecure registry must be the actual location you intend to use (FIXME: add a note that what you put here in the end will point at THIS host - the deployer), but the private Docker Registry does not have to be running yet.  
    ```
    cd && vim cloud-config.yaml
    ```
    Contents:
    ```
    #cloud-config
    
    ssh_authorized_keys:
      - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDGdByTgSVHq.......
    
    manage_etc_hosts: localhost
    
    coreos:
      units:
        - name: docker.service
          drop-ins:
            - name: 50-insecure-registry.conf
              content: |
                [Service]
                Environment='DOCKER_OPTS=--insecure-registry="10.101.10.16:5000"'
          command: restart
    ```  
  - Find the device name of the disk you set the deployer to boot to, using `sudo fdisk -l` or similar. The example coreos-install command below assumes you found this device at '/dev/sda'.
  - If you need to configure a static DHCP lease in your router for your deployer node this is a good time to do it, so that you get the new IP when the system reboots.
  - Run coreos-install to install to disk:

    ```
    sudo coreos-install -d /dev/sda -C stable -c ~/cloud-config.yaml
    sudo reboot
    ```

  - Check out this repo:

    ```
    git clone https://github.com/ropsoft/KPC.git
    ```

  - Build container with IPMI tools:

    ```
    pushd KPC/dockerfiles/
    docker build -t ipmitool ipmitool/
    popd
    ```

  - Export environment vars to configure, and substitute those vars in

    ```
    # what channel to deploy to nodes
    export KPC_coreos_channel=stable
    find ./ -type f -exec sed -i -e "s/KPC_coreos_channel/${KPC_coreos_channel}/" {} \;
    
    # what version within chosen channel
    export KPC_coreos_version='1010.5.0'
    find ./ -type f -exec sed -i -e "s/KPC_coreos_version/${KPC_coreos_version}/" {} \;
    
    # used both as-named and for image base url option of coreos-install
    export KPC_bootcfg_endpoint='10.101.10.16'
    find ./ -type f -exec sed -i -e "s/KPC_bootcfg_endpoint/${KPC_bootcfg_endpoint}/" {} \;

    # with a little trial and error you should be able to pass a list if you want
    export KPC_ssh_authorized_keys='ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDGdByTgSVHq.......'
    # sed delimiter changed to avoid escaping '/'
    find ./ -type f -exec sed -i -e "s|KPC_ssh_authorized_keys|${KPC_ssh_authorized_keys}|" {} \;

    # create a token to bootstrap etcd - remember to set size correctly
    export KPC_discovery_token="$(curl -w "\n" 'https://discovery.etcd.io/new?size=3')"
    # sed delimiter changed to avoid escaping '/'
    find ./ -type f -exec sed -i -e "s|KPC_discovery_token|${KPC_discovery_token}|" {} \;

    # a hint on how to find which IP etcd should use for some options
    # NOTE: This ends up used as regex; periods are not literal. This is lesser evil than esacping them here.
    # Should be ok as long as no two are adjacent for some reason, like "10..10.10."
    # (i.e.: the single character they match should always be a literal '.')
    export KPC_private_subnet_hint="10.101.10."
    find ./ -type f -exec sed -i -e "s/KPC_private_subnet_hint/${KPC_private_subnet_hint}/" {} \;
    ```

  - Get CoreOS image assets:

    ```
    ./bootcfg/scripts/get-coreos "${KPC_coreos_channel}" "${KPC_coreos_version}" ./bootcfg/assets
    ```

  - Start dnsmasq and bootcfg containers. Check the value of --dhcp-range on second command:

    ```
    docker run -p 8080:8080 --rm -v $PWD/bootcfg:/var/lib/bootcfg:Z -v $PWD/bootcfg/groups/etcd-install:/var/lib/bootcfg/groups:Z quay.io/coreos/bootcfg:v0.3.0 -address=0.0.0.0:8080 -log-level=debug
    docker run --net=host --rm --cap-add=NET_ADMIN quay.io/coreos/dnsmasq -d -q --dhcp-range=10.101.10.1,proxy,255.255.255.0 --enable-tftp --tftp-root=/var/lib/tftpboot --dhcp-userclass=set:ipxe,iPXE --pxe-service=tag:#ipxe,x86PC,"PXE chainload to iPXE",undionly.kpxe --pxe-service=tag:ipxe,x86PC,"iPXE",http://"${KPC_bootcfg_endpoint}":8080/boot.ipxe --log-queries --log-dhcp
    ```
