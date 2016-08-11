#!/bin/bash

#FIXME
# Require git working copy to be clean so we can template with immunity...
# If not clean recommend a git reset (with a data loss warning), then exit 1

# source some files to determine CoreOS channel and version, then sub them in
source /etc/coreos/update.conf
source /etc/os-release
echo "This deploy host is booted to CoreOS ${VERSION} from the ${GROUP} release channel."
echo " - Will download and deploy CoreOS ${VERSION} from release channel ${GROUP} to any target nodes needing install."
find ./bootcfg -type f -exec sed -i -e "s/KPC_coreos_channel/${GROUP}/" {} \;
find ./bootcfg -type f -exec sed -i -e "s/KPC_coreos_version/${VERSION}/" {} \;

# needed for next sections
SSH_CONNECTION_ARRAY=( ${SSH_CONNECTION} )

# how do nodes reach bootcfg? where do they get coreos images to boot?
echo "Your SSH session to this deploy host is to its IP address '${SSH_CONNECTION_ARRAY[2]}'; this address is assumed to be on the management network."
export KPC_bootcfg_endpoint="${SSH_CONNECTION_ARRAY[2]}"
echo " - Will instruct booting nodes to reach bootcfg service at ${KPC_bootcfg_endpoint}:8080 for configs and images."
find ./bootcfg -type f -exec sed -i -e "s/KPC_bootcfg_endpoint/${KPC_bootcfg_endpoint}/" {} \;

# a hint for our ip-metadata-kpc systemd unit to determine which IP/interface services like etcd2 should bootstrap on
export KPC_private_subnet_hint="${KPC_bootcfg_endpoint%.*}."
find ./bootcfg -type f -exec sed -i -e "s/KPC_private_subnet_hint/${KPC_private_subnet_hint}/" {} \;

# MAY BE ADDED LATER... This is a partial implementation for manual selection option of the subnet hint/bootcfg endpoint
# choose bootcfg endpoint and mgmt subnet hint
# we assume IPv4, and that the CIDR mask is /24 or larger (that is, nodes have the same first 3 octets for their IP on this network)
#echo "Please choose the IP address that represents this host's interface to the management network:"
#select ipadr in $(ip -4 -o addr show scope global | awk '{print $4}'); do echo $ipadr selected; export THEIP="${ipadr}"; break; done

# get list of authorized_keys for the current user and pass them along to the booted nodes
mapfile -t pubkeys_pre < ~/.ssh/authorized_keys
pubkeys=()
echo
echo "WARNING WARNING WARNING"
echo "Nodes booting from network and installing will be configured to allow the core user to SSH "
echo "in with **ALL** of the keys found in ~/.ssh/authorized_keys. These include:"
echo
for key in "${pubkeys_pre[@]}"; do
    if [[ "${key}" != '' && ! "${key}" =~ ^# ]]
    then
        echo "${key}" | sed -e 's/\(.\{25\}\).*\(.\{25\}\)/ - \1 ... ... ... \2/'
        pubkeys+=("\"${key}\",")
    fi
done
echo

pubkeys_string_temp="${pubkeys[@]}"
export KPC_ssh_authorized_keys="${pubkeys_string_temp%,}"

# sed delimiter changed to avoid escaping '/'
find ./bootcfg -type f -exec sed -i -e "s|KPC_ssh_authorized_keys|${KPC_ssh_authorized_keys}|" {} \;



# create a token to bootstrap etcd - remember to set size to the number of target nodes
export KPC_discovery_token="$(curl -w "\n" 'https://discovery.etcd.io/new?size=3')"
# sed delimiter changed to avoid escaping '/'
find ./bootcfg -type f -exec sed -i -e "s|KPC_discovery_token|${KPC_discovery_token}|" {} \;

