#!/bin/bash

# reset templating from last run
git status | grep modified | awk '{print $2}' | grep -v template-bootcfg.bash | xargs git checkout

#kill container from last run
docker ps -a | grep bootcfg | awk '{print $1}' | xargs -I{} bash -c 'docker kill {} && docker rm {}'

# remove ignition.json from last run
rm -v ignition.json

this_script="$(basename $0)"

# next two functions:
# http://stackoverflow.com/questions/20762575/explanation-of-convertor-of-cidr-to-netmask-in-linux-shell-netmask2cdir-and-cdir
mask2cdr ()
{
   # Assumes there's no "255." after a non-255 byte in the mask
   local x=${1##*255.}
   set -- 0^^^128^192^224^240^248^252^254^ $(( (${#1} - ${#x})*2 )) ${x%%.*}
   x=${1%%$3*}
   echo $(( $2 + (${#x}/4) ))
}

cdr2mask ()
{
   # Number of args to shift, 255..255, first non-255 byte, zeroes
   set -- $(( 5 - ($1 / 8) )) 255 255 255 255 $(( (255 << (8 - ($1 % 8))) & 255 )) 0 0 0
   [ $1 -gt 1 ] && shift $1 || shift
   echo ${1-0}.${2-0}.${3-0}.${4-0}
}

if [[ "$(git rev-parse --show-toplevel)" != "${PWD}" ]]
then
    echo "ERROR: ${this_script} cannot continue"
    echo "${this_script} must be run from the root of the kpc git repository as 'sudo -E ./script.bash'"
    echo ""
    echo "FIXME: add some notes on how this is determined in case it is flaky"
    echo "formatting here is terrible"
fi

# source some files to determine CoreOS channel and version, then sub them in
[ -e /usr/share/coreos/update.conf ] && source /usr/share/coreos/update.conf
[ -e /etc/coreos/update.conf ] && source /etc/coreos/update.conf
source /etc/os-release

echo "This deploy host is booted to CoreOS ${VERSION} from the ${GROUP} release channel."
echo " - Will download and deploy CoreOS ${VERSION} from release channel ${GROUP} to any target nodes needing install."
grep -rlZ KPC_coreos_channel . | grep -zZv "${this_script}" | xargs -0 sed -i -e "s/KPC_coreos_channel/${GROUP}/"
grep -rlZ KPC_coreos_version . | grep -zZv "${this_script}" | xargs -0 sed -i -e "s/KPC_coreos_version/${VERSION}/"

# needed for next sections
SSH_CONNECTION_ARRAY=( ${SSH_CONNECTION} )

# how do nodes reach bootcfg? where do they get coreos images to boot?
echo "Your SSH session to this deploy host is to its IP address '${SSH_CONNECTION_ARRAY[2]}'; this address is assumed to be on the management network."
export KPC_bootcfg_endpoint="${SSH_CONNECTION_ARRAY[2]}"
echo " - Will instruct booting nodes to reach bootcfg service at ${KPC_bootcfg_endpoint}:8080 for configs and images."
grep -rlZ KPC_bootcfg_endpoint . | grep -zZv "${this_script}" | xargs -0 sed -i -e "s/KPC_bootcfg_endpoint/${KPC_bootcfg_endpoint}/"

# a hint for our ip-metadata-kpc systemd unit to determine which IP/interface services like etcd2 should bootstrap on
export KPC_private_subnet_hint="${KPC_bootcfg_endpoint%.*}."
grep -rlZ KPC_private_subnet_hint . | grep -zZv "${this_script}" | xargs -0 sed -i -e "s/KPC_private_subnet_hint/${KPC_private_subnet_hint}/"

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

if [[ ${#pubkeys[@]} < 1 ]]
then
    echo ' - NO KEYS (you may not be able to log in to booted nodes!!)'
fi

echo

pubkeys_string_temp="${pubkeys[@]}"
export KPC_ssh_authorized_keys="${pubkeys_string_temp%,}"

# sed delimiter changed to avoid escaping '/'
grep -rlZ KPC_ssh_authorized_keys . | grep -zZv "${this_script}" | xargs -0 sed -i -e "s|KPC_ssh_authorized_keys|${KPC_ssh_authorized_keys}|"



# create a token to bootstrap etcd - remember to set size to the number of target nodes
echo "Retrieving an etcd discovery token for installed nodes to bootstrap with"
#FIXME need a more elegant way to set the cluster size
export KPC_discovery_token="$(curl -w "\n" 'https://discovery.etcd.io/new?size=3' 2>/dev/null)"
echo "Got ${KPC_discovery_token}"
#FIXME error out if no token
# sed delimiter changed to avoid escaping '/'
grep -rlZ KPC_discovery_token . | grep -zZv "${this_script}" | xargs -0 sed -i -e "s|KPC_discovery_token|${KPC_discovery_token##*/}|"

echo "Downloading required coreos images using upstream get-coreos script"
bootcfg/scripts/get-coreos "${GROUP}" "${VERSION}" ./bootcfg/assets

echo "Starting up a temporary bootcfg instance to render the Ignition config this host will run after install/reboot"
docker run -d -p 8080:8080 -v $PWD/bootcfg:/var/lib/bootcfg:Z \
    -v $PWD/bootcfg/groups/kolla:/var/lib/bootcfg/groups:Z \
    quay.io/coreos/bootcfg:v0.4.0 -address=0.0.0.0:8080 -log-level=debug

sleep 2

echo "Retrieving Ignition config for deploy host"
curl "http://10.101.0.15:8080/ignition?mac=00-00-00-00-00-00&modekey=deployhost&etcd_discovery_id=3b7d535dc6c23ba5d382d5944743fb91&coreos_private_subnet_hint=10.101.0." --retry 5 --retry-delay 2 -o ignition.json


DEVICE=/dev/sda
read -r -p "Are you sure you want to run coreos-install and ERASE ${DEVICE}? [y/N] " response
response=${response,,}    # tolower
if [[ ! $response =~ ^(yes|y)$ ]]
then
    echo "You said no"
    exit 1
fi



coreos-install -d "${DEVICE}" -C "${GROUP}" -V "${VERSION}" -i ignition.json -b http://"${KPC_bootcfg_endpoint}":8080/assets/coreos
udevadm settle


# most of the rest of this script is code borrowed from the upstream coreos-install script

error_output() {
    echo "Error: return code $? from $BASH_COMMAND" >&2
}

WORKDIR=$(mktemp --tmpdir -d coreos-install.XXXXXXXXXX)
trap "error_output ; rm -rf '${WORKDIR}'" EXIT

# The ROOT partition should be #9 but make no assumptions here!
# Also don't mount by label directly in case other devices conflict.
ROOT_DEV=$(blkid -t "LABEL=ROOT" -o device "${DEVICE}"*)

mkdir -p "${WORKDIR}/rootfs"
case $(blkid -t "LABEL=ROOT" -o value -s TYPE "${ROOT_DEV}") in
  "btrfs") mount -t btrfs -o subvol=root "${ROOT_DEV}" "${WORKDIR}/rootfs" ;;
  *)       mount "${ROOT_DEV}" "${WORKDIR}/rootfs" ;;
esac
trap "error_output ; umount '${WORKDIR}/rootfs' && rm -rf '${WORKDIR}'" EXIT

if [[ -n "${CLOUDINIT}" ]]; then
  echo "Installing cloud-config..."
  mkdir -p "${WORKDIR}/rootfs/var/lib/coreos-install"
  cp "${CLOUDINIT}" "${WORKDIR}/rootfs/var/lib/coreos-install/user_data"
fi

if [[ -n "${COPY_NET}" ]]; then
  echo "Copying network units to root partition."
  # Copy the entire directory, do not overwrite anything that might exist there, keep permissions, and copy the resolve.conf link as a file.
  cp --recursive --no-clobber --preserve --dereference /run/systemd/network/* "${WORKDIR}/rootfs/etc/systemd/network"
fi

configs_destination="${WORKDIR}/rootfs/etc/kpc"
mkdir -p "${configs_destination}"
cp -r bootcfg "${configs_destination}"
cp -r dockerfiles "${configs_destination}"

umount "${WORKDIR}/rootfs"
trap "error_output ; rm -rf '${WORKDIR}'" EXIT

rm -rf "${WORKDIR}"
trap - EXIT


