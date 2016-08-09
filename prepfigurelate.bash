#!/bin/bash

# source files to determine CoreOS channel and version
source /etc/coreos/update.conf
source /etc/os-release
find ./ -type f -exec sed -i -e "s/KPC_coreos_channel/${GROUP}/" {} \;
find ./ -type f -exec sed -i -e "s/KPC_coreos_version/${VERSION}/" {} \;

# choose bootcfg endpoint and mgmt subnet hint
# we assume IPv4, and that the CIDR mask is /24 or larger (that is, nodes have the same first 3 octets for their IP on this network)
echo "Please choose the IP address that represents this host's interface to the management network:"
select ipadr in $(ip -4 -o addr show scope global | awk '{print $4}'); do echo $ipadr selected; export THEIP="${ipadr}"; break; done

#FIXME ##^^^don't do that, use SSH_CONNECTION env var

# used both as-named and for image base url option of coreos-install
export KPC_bootcfg_endpoint='10.101.0.15'
find ./ -type f -exec sed -i -e "s/KPC_bootcfg_endpoint/${KPC_bootcfg_endpoint}/" {} \;

# with a little trial and error you should be able to pass a list if you want
export KPC_ssh_authorized_keys='ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDGdByTgSVHq.......'
# sed delimiter changed to avoid escaping '/'
find ./ -type f -exec sed -i -e "s|KPC_ssh_authorized_keys|${KPC_ssh_authorized_keys}|" {} \;

# create a token to bootstrap etcd - remember to set size to the number of target nodes
export KPC_discovery_token="$(curl -w "\n" 'https://discovery.etcd.io/new?size=3')"
# sed delimiter changed to avoid escaping '/'
find ./ -type f -exec sed -i -e "s|KPC_discovery_token|${KPC_discovery_token}|" {} \;

# a hint on how to find which IP etcd should use for some options
# NOTE: This ends up used as regex; periods are not literal. This is lesser evil than esacping them here.
# Should be ok as long as no two are adjacent for some reason, like "10..10.0."
# (i.e.: the single character they match should always be a literal '.')
export KPC_private_subnet_hint="10.101.0."
find ./ -type f -exec sed -i -e "s/KPC_private_subnet_hint/${KPC_private_subnet_hint}/" {} \;
