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
  - Note the IP the system gets, as we will SSH to the host in next steps
    ```
    ip a
    ```
  - SSH to the host from your machine, logging in as **core** using the password you just set.
  - Create a cloud-init or ignition config that sets an SSH key for **core** and sets Docker to use an insecure registry. We will pass this file to `coreos-install` to use while installing the OS to disk. The IP or hostname of the insecure registry must be the actual location you intend to use (FIXME: add a note that what you put here in the end will point at THIS host - the deployer), but the private Docker Registry does not have to be running yet.  
    ```
    #cloud-config
    
    ssh_authorized_keys:
      - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDGdByTgSVHq.......
    
    manage_etc_hosts: "localhost"
    
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
  - Find the device name of the disk you set the deployer to boot to, using `fdisk -l` or similar. The example coreos-install command below assumes you found this device at '/dev/sda'.
  - If you need to configure a static DHCP lease for your deployer node this is a good time to do it, so that you get the new IP when the system reboots.
  - Run coreos-install to install to disk:
    ```
    coreos-install -d /dev/sda -C stable -c ~/cloud-config.yaml
    ```
