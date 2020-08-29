#!/usr/bin/env bash

set -Eeuo pipefail
shopt -s expand_aliases
alias die='EXIT=$? LINE=$LINENO error_exit'
trap die ERR
trap cleanup EXIT
function error_exit() {
  trap - ERR
  local DEFAULT='Unknown failure occured.'
  local REASON="\e[97m${1:-$DEFAULT}\e[39m"
  local FLAG="\e[91m[ERROR] \e[93m$EXIT@$LINE"
  msg "$FLAG $REASON"
  [ ! -z ${CTID-} ] && cleanup_failed
  exit $EXIT
}
function warn() {
  local REASON="\e[97m$1\e[39m"
  local FLAG="\e[93m[WARNING]\e[39m"
  msg "$FLAG $REASON"
}
function info() {
  local REASON="$1"
  local FLAG="\e[36m[INFO]\e[39m"
  msg "$FLAG $REASON"
}
function msg() {
  local TEXT="$1"
  echo -e "$TEXT"
}
function section() {
  local REASON="  \e[97m$1\e[37m"
  printf -- '-%.0s' {1..100}; echo ""
  msg "$REASON"
  printf -- '-%.0s' {1..100}; echo ""
  echo
}
function cleanup_failed() {
  if [ ! -z ${MOUNT+x} ]; then
    pct unmount $CTID
  fi
  if $(pct status $CTID &>/dev/null); then
    if [ "$(pct status $CTID | awk '{print $2}')" == "running" ]; then
      pct stop $CTID
    fi
    pct destroy $CTID
  elif [ "$(pvesm list $STORAGE --vmid $CTID)" != "" ]; then
    pvesm free $ROOTFS
  fi
}
function cleanup() {
  popd >/dev/null
  rm -rf $TEMP_DIR
}
function load_module() {
  if ! $(lsmod | grep -Fq $1); then
    modprobe $1 &>/dev/null || \
      die "Failed to load '$1' module."
  fi
  MODULES_PATH=/etc/modules
  if ! $(grep -Fxq "$1" $MODULES_PATH); then
    echo "$1" >> $MODULES_PATH || \
      die "Failed to add '$1' module to load at boot."
  fi
}
function box_out() {
  set +u
  local s=("$@") b w
  for l in "${s[@]}"; do
	((w<${#l})) && { b="$l"; w="${#l}"; }
  done
  tput setaf 3
  echo " -${b//?/-}-
| ${b//?/ } |"
  for l in "${s[@]}"; do
	printf '| %s%*s%s |\n' "$(tput setaf 7)" "-$w" "$l" "$(tput setaf 3)"
  done
  echo "| ${b//?/ } |
 -${b//?/-}-"
  tput sgr 0
  set -u
}


# Colour
RED=$'\033[0;31m'
YELLOW=$'\033[1;33m'
GREEN=$'\033[0;32m'
WHITE=$'\033[1;37m'
NC=$'\033[0m'

# Detect modules and automatically load at boot
load_module aufs
load_module overlay

# Set Temp Folder
TEMP_DIR=$(mktemp -d)
pushd $TEMP_DIR >/dev/null


# Download external scripts
wget -qL https://raw.githubusercontent.com/ahuacate/proxmox-node/master/scripts/fileserver_setup_ct_18.04.sh
#chmod +x fileserver_setup_ct_18.04.sh

#########################################################################################
# This script is for creating your Proxmox Fileserver (cyclone-01) Container		      	#
#                                                                 						          #
# Tested on Proxmox Version : pve-manager/6.1-3/37248ce6 (running kernel: 5.3.10-1-pve) #
#########################################################################################

# Command to run script
# bash -c "$(wget -qLO - https://raw.githubusercontent.com/ahuacate/proxmox-node/master/scripts/fileserver_create_ct_18.04.sh)"




# Introduction
clear
echo
box_out '#### PLEASE READ CAREFULLY ####' '' 'This script will create a Proxmox File Server container.' 'User input is required. The script may create, edit and/or change system' 'files on your Proxmox host. When an optional default setting is provided' 'you may accept the default by pressing ENTER on your keyboard or' 'change it to your preferred value.' '' 'The Proxmox Fileserver container will be configured with NFS4.1,' 'Samba and Webmin so you can manage your fileserver.'
echo
sleep 1


# Select storage location
STORAGE_LIST=( $(pvesm status -content rootdir | awk 'NR>1 {print $1}') )
if [ ${#STORAGE_LIST[@]} -eq 0 ]; then
  warn "'Container' needs to be selected for at least one storage location."
  die "Unable to detect valid storage location."
elif [ ${#STORAGE_LIST[@]} -eq 1 ]; then
  STORAGE=${STORAGE_LIST[0]}
else
  msg "\n\nMore than one storage locations detected.\n"
  PS3=$'\n'"Which storage location would you like to use (Recommend local-zfs) ? "
  select s in "${STORAGE_LIST[@]}"; do
    if [[ " ${STORAGE_LIST[@]} " =~ " ${s} " ]]; then
      STORAGE=$s
      break
    fi
    echo -en "\e[1A\e[K\e[1A"
  done
fi
info "Using '$STORAGE' for storage location."
clear
echo


# Message about setting variables
section "Setting File Server Variables"
msg "We need to set some variables. Variables are used to create and setup
your Proxmox File Server container. The next steps requires your input.

You can accept our default values by pressing ENTER on your keyboard.
Or overwrite the default value by typing in your own value and
press ENTER to accept/continue."
echo
echo


# Set Fileserver CT CT_HOSTNAME
read -p "Enter CT Hostname: " -e -i cyclone-01 CT_HOSTNAME
CT_HOSTNAME=${CT_HOSTNAME,,}
info "CT hostname is set: ${YELLOW}$CT_HOSTNAME${NC}."
echo

# Set Fileserver CT IPv4 Address
while true; do
read -p "Enter CT IPv4 address: " -e -i 192.168.1.10/24 CT_IP
if [ $(expr "$CT_IP" : '[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\/[0-9][0-9]*$' >/dev/null; echo $?) == 0 ] && [ $(ping -s 1 -c 2 "$(echo "$CT_IP" | sed  's/\/.*//g')" > /dev/null; echo $?) != 0 ]; then
info "The CT IP address is set: ${YELLOW}$CT_IP${NC}."
echo
break
elif [ $(expr "$CT_IP" : '[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\/[0-9][0-9]*$' >/dev/null; echo $?) != 0 ]; then
warn "There are problems with your input:
1.  Your IP address is incorrectly formatted. It must be in the IPv4 format
including a subnet mask (i.e xxx.xxx.xxx.xxx/24 ).
Try again..."
echo
elif [ $(expr "$CT_IP" : '[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\/[0-9][0-9]*$' >/dev/null; echo $?) == 0 ] && [ $(ping -s 1 -c 2 "$(echo "$CT_IP" | sed  's/\/.*//g')" > /dev/null; echo $?) == 0 ]; then
warn "There are problems with your input:
1. Your IP address meets the IPv4 standard, BUT
2. Your IP address $(echo "$CT_IP" | sed  's/\/.*//g') is all ready in-use on your LAN.
Try again..."
echo
fi
done

# Set container VLAN CT_TAG
read -p "Is your network VLAN aware [yes/no]?: " -r
if [[ "$REPLY" == "y" || "$REPLY" == "Y" || "$REPLY" == "yes" || "$REPLY" == "Yes" ]]; then
  if [ $(echo "$(echo "$CT_IP" | sed  's/\/.*//g')" | awk -F"." '{print $3}') -gt 1 ];then
    msg "Hint: "${CT_HOSTNAME^}" IPv4 address is $(echo "$CT_IP" | sed  's/\/.*//g') so your VLAN tag is $(echo "$(echo "$CT_IP" | sed  's/\/.*//g')" | awk -F"." '{print $3}')."
    read -p "Enter the CT network VLAN tag: " -e -i $(echo "$(echo "$CT_IP" | sed  's/\/.*//g')" | awk -F"." '{print $3}') CT_TAG
    info "The CT VLAN is set: ${YELLOW}$CT_TAG${NC}."
  else
    CT_TAG=1
    info "The CT VLAN is set: ${YELLOW}disabled${NC}."
  fi
else
  CT_TAG=1
  info "The CT VLAN is set: ${YELLOW}disabled${NC}."
fi
echo

# Set container Gateway IPv4 Address
msg "Hint: "${CT_HOSTNAME^}" IPv4 address is $(echo "$CT_IP" | sed  's/\/.*//g') so your Gateway should be $(ip route show | grep default | awk '{print $3}')."
read -p "Enter a Gateway IPv4 address: " -e -i $(ip route show | grep default | awk '{print $3}') CT_GW
info "The CT VLAN is set: ${YELLOW}$CT_GW${NC}."
echo

# Set container ID
pct list > pct_list
CTID_IP="$(echo "$CT_IP" | sed  's/\/.*//g' | awk -F"." '{print $4}')"
if [ $CTID_IP -lt 100 ]; then
  CTID_TEMP=$(( $CTID_IP + 100 ))
elif [ $CTID_IP -gt 100 ]; then
  CTID_TEMP=$CTID_IP
fi
msg "Attempting to set and match your File Server CT ID with the host section
value of your CT IP address: $(echo "$CT_IP" | sed  's/\/.*//g' | awk -F "." '{print $1, $2, $3, "\033[1;33m"$4"\033[0m"}' | sed 's/ /./g').
Attempting to set "${CT_HOSTNAME^}" CT ID as: ${YELLOW}$CTID_TEMP${NC}.
If CT ID ${YELLOW}$CTID_TEMP${NC} is unavailable a indexed or random CT ID will be assigned."
sleep 2
if [ $CTID_IP -lt 100 ] && [ "$(cat pct_list | grep -w $(( $CTID_IP + 100 )) > /dev/null; echo $?)" != 0 ]; then
  CTID=$(( $CTID_IP + 100 ))
  info "The CT ID is set: ${YELLOW}$CTID${NC}."
elif [ $CTID_IP -gt 100 ] && [ "$(cat pct_list | grep -w $CTID_IP > /dev/null; echo $?)" != 0 ]; then
  CTID=$CTID_IP
  info "The CT ID is set: ${YELLOW}$CTID${NC}."
elif [ "$(cat pct_list | grep -w $(( $CTID_IP + 100 )) > /dev/null; echo $?)" != 0 ] || [ "$(cat pct_list | grep -w $CTID_IP > /dev/null; echo $?)" != 0 ]; then
  echo
  read -p "CT ID ${YELLOW}$CTID_TEMP${NC} is NOT available.
Generating a valid CT ID (press ENTER to accept or type change): " -e -i $(pvesh get /cluster/nextid) CTID
  info "The CT ID is set: ${YELLOW}$CTID${NC}."
fi
echo

# Set container Virtual Disk Size
read -p "Enter CT Virtual Disk Size (Gb): " -e -i 10 CT_DISK_SIZE
info "CT virtual disk is set: ${YELLOW}$CT_DISK_SIZE Gb${NC}."
echo

# Set container Memory
read -p "Enter amount of CT RAM Memory to be allocated (Gb): " -e -i 2048 CT_RAM
info "CT allocated memory is set: ${YELLOW}$CT_RAM Mb${NC}."
echo

# Set container password
while true; do
  read -p "Enter CT root password: " -e -i ahuacate CT_PWD
  echo
  read -p "Confirmation. Retype your CT root password (again): " -e -i ahuacate CT_PWD_CHECK
  echo "Validating your root password..."
  if [ "$CT_PWD" = "$CT_PWD_CHECK" ];then
    info "Container root password is set: ${YELLOW}$CT_PWD${NC}."
    break
  elif [ "$CT_PWD" != "$CT_PWD_CHECK" ]; then
    echo "Your inputs ${RED}$CT_PWD${NC} and ${RED}$CT_PWD_CHECK${NC} do NOT match.\nTry again..."
  fi
done
echo


#### Creating the Proxmox Container ####
section "Creating the Proxmox CT: ${CT_HOSTNAME^}"

# Download latest OS LXC template
msg "Updating Proxmox LXC template list..."
pveam update >/dev/null
msg "Downloading Proxmox LXC template..."
OSTYPE=ubuntu
OSVERSION=${OSTYPE}-18
mapfile -t TEMPLATES < <(pveam available -section system | sed -n "s/.*\($OSVERSION.*\)/\1/p" | sort -t - -k 2 -V)
TEMPLATE="${TEMPLATES[-1]}"
pveam download local $TEMPLATE >/dev/null ||
  die "A problem occurred while downloading the LXC template."
ARCH=$(dpkg --print-architecture)
TEMPLATE_STRING="local:vztmpl/${TEMPLATE}"


# Create LXC
msg "Creating LXC container..."
if [ $CT_TAG -gt 1 ]; then
  pct create $CTID $TEMPLATE_STRING --arch $ARCH --cores 1 --hostname $CT_HOSTNAME --cpulimit 1 --memory $CT_RAM --features nesting=1,mount=nfs4 \
    --net0 name=eth0,bridge=vmbr0,tag=$CT_TAG,firewall=1,gw=$CT_GW,ip=$CT_IP,type=veth \
    --ostype $OSTYPE --rootfs $STORAGE:$CT_DISK_SIZE,acl=1 --swap 256 --unprivileged 0 --onboot 1 --startup order=1 --password $CT_PWD >/dev/null
elif [ $CT_TAG == 1 ]; then
  pct create $CTID $TEMPLATE_STRING --arch $ARCH --cores 1 --hostname $CT_HOSTNAME --cpulimit 1 --memory $CT_RAM --features nesting=1,mount=nfs4 \
    --net0 name=eth0,bridge=vmbr0,firewall=1,gw=$CT_GW,ip=$CT_IP,type=veth \
    --ostype $OSTYPE --rootfs $STORAGE:$CT_DISK_SIZE,acl=1 --swap 256 --unprivileged 0 --onboot 1 --startup order=1 --password $CT_PWD >/dev/null
fi
echo


#### Creating the ZPOOL Tank ####
section "Checking for Zpool storage availability."

# Set ZFS pool name
msg "Setting the ZFS Pool name..."
read -p "Enter your desired ZFS pool name (i.e default is tank): " -e -i tank POOL
POOL=${POOL,,}
info "ZFS pool name is set: ${YELLOW}$POOL${NC}."
echo


# Confirm Boot Disks
msg "Confirming Proxmox PVE, OS and Boot hard disk ID..."
# boot disks
fdisk -l 2>/dev/null | grep -E 'BIOS boot|EFI System' | awk '{ print $1 }' | sort > boot_disklist_var01
cat boot_disklist_var01 | sed 's/[0-9]*//g' | awk '!seen[$0]++' > boot_disklist_tmp01
for f in $(cat boot_disklist_tmp01 | sed 's|/dev/||')
  do read dev
    echo "$(fdisk -l /dev/"$f" | grep -E 'Solaris /usr & Apple ZFS' | awk '{print $1}')" >> boot_disklist_var01
done < boot_disklist_tmp01
# Create raw whole device /dev/sd?
if grep -Fq "$(cat boot_disklist_var01 | sed 's/[0-9]*//g' | awk '!seen[$0]++')" boot_disklist_var01; then
  cat boot_disklist_var01 | sed 's/[0-9]*//g' | awk '!seen[$0]++' >> boot_disklist_var01
fi
# Sort the list
sort -o boot_disklist_var01 boot_disklist_var01
# Add Linux by-id to column 2 & Disk Size to column 3,4 & Disk Type to column 5
for f in $(cat boot_disklist_var01 | awk '{ print $1 }' | sed 's|/dev/||')
  do read dev
    echo "$dev" "$(ls -l /dev/disk/by-id/ata* | grep -w "$f" | awk '{ print $9 }' | sed 's|/dev/disk/by-id/||')" "$(fdisk -l /dev/"$f" | grep -w "Disk /dev/"$f"" | awk '{print $3,$4}' | sed 's|,||')" "$(if [ $(cat /sys/block/"$(echo $f | sed 's/[0-9]*//g')"/queue/rotational) == 0 ];then echo "ssd"; else echo "harddisk";fi)" >> boot_disklist
done < boot_disklist_var01
echo


# Confirm Root File System Partitioned Cache & Log Disks
if [ $(fdisk -l $(fdisk -l 2>/dev/null | grep -E 'BIOS boot|EFI System'| awk '{ print $1 }' | sort | sed 's/[0-9]*//g' | awk '!seen[$0]++') | grep -Ev 'BIOS boot|EFI System|Solaris /usr & Apple ZFS' | grep -E 'Linux filesystem' | awk '{ print $1 }' | wc -l)  -ge 2 ]; then
  set +Eeuo pipefail
  msg "Confirming Proxmox Root File System partitions for\nZFS ARC or L2ARC Cache & ZIL (logs) on $HOSTNAME ..."
  echo
  read -p "Have you ${WHITE}already partitioned${NC} $HOSTNAME root filesystem disk(s) for ARC or L2ARC Cache and ZIL [yes/no]?: " -r
  if [[ "$REPLY" == "y" || "$REPLY" == "Y" || "$REPLY" == "yes" || "$REPLY" == "Yes" ]]; then
    while true
    do
      fdisk -l $(fdisk -l 2>/dev/null | grep -E 'BIOS boot|EFI System'| awk '{ print $1 }' | sort | sed 's/[0-9]*//g' | awk '!seen[$0]++') | grep -Ev 'BIOS boot|EFI System|Solaris /usr & Apple ZFS' | grep -E 'Linux filesystem' | awk '{ print $1 }' > zfs_rootcachezil_disklist_var01
      for f in $(cat zfs_rootcachezil_disklist_var01 | awk '{ print $1 }' | sed 's|/dev/||')
        do read dev
          echo "$dev" "$(ls -l /dev/disk/by-id/ata* | grep -w "$f" | awk '{ print $9 }' | sed 's|/dev/disk/by-id/||')" "$(fdisk -l /dev/"$f" | grep -w "Disk /dev/"$f"" | awk '{print $3, $4}' | sed 's|,||')" "$(if [ $(cat /sys/block/"$(echo $f | sed 's/[0-9]*//g')"/queue/rotational) == 0 ];then echo "ssd"; else echo "harddisk";fi)" >> zfs_rootcachezil_disklist_var02
      done < zfs_rootcachezil_disklist_var01
      msg "There are two different SSD caches that a ZFS pool can make use of:\n  1.  ZFS Intent Log, or ZIL, to buffer WRITE operations.\n  2.  ARC and L2ARC cache which are meant for READ operations.\nIn the next steps you will asked to select ZIL and ARC or L2ARC Cache disks.\nRemember ARC or L2ARC disks will be larger (default 64GiB) than ZIL disks (default 8GiB).\n\nSelect the disk, or two matching disks if you are configured for raid, to be used for: ${YELLOW}ARC or L2ARC Cache${NC} (excluding ZIL disks)."
      menu() {
        echo "Available options:"
        for i in "${!options[@]}"; do 
            printf "%3d%s) %s\n" $((i+1)) "${choices[i]:- }" "${options[i]}"
        done
        if [[ "$msg" ]]; then echo "$msg"; fi
      }
      mapfile -t options < zfs_rootcachezil_disklist_var02
      prompt="Check an option to select ARC or L2ARC cache\ndisk partitions (again to uncheck, ENTER when done): "
      while menu && read -rp "$prompt" num && [[ "$num" ]]; do
        [[ "$num" != *[![:digit:]]* ]] &&
        (( num > 0 && num <= ${#options[@]} )) ||
        { msg="Invalid option: $num"; continue; }
        ((num--)); msg="${options[num]} was ${choices[num]:+un}checked"
        [[ "${choices[num]}" ]] && choices[num]="" || choices[num]="+"
      done
      echo
      printf "Your selected ARC or L2ARC cache disk partitions are:\n"; msg=" nothing"
      for i in ${!options[@]}; do
        [[ "${choices[i]}" ]] && { printf "${YELLOW}Disk ID:${NC}  %s\n" "${options[i]}"; msg=""; } && echo $({ printf "%s" "${options[i]}"; msg=""; }) >> zpool_rootcache_disklist
      done
      unset -f i
      echo
      awk -F " "  'NR==FNR {a[$1];next}!($1 in a) {print $0}' zpool_rootcache_disklist zfs_rootcachezil_disklist_var02 | awk '!seen[$0]++' | sort > zfs_rootzil_disklist_var01
      msg "Now select the disk, or two matching disks if you are configured for raid, to be used for: ${YELLOW}ZIL Cache${NC}."
      menu() {
        echo "Available options:"
        for i in ${!options[@]}; do 
            printf "%3d%s) %s\n" $((i+1)) "${choices[i]:- }" "${options[i]}"
        done
        if [[ "$msg" ]]; then echo "$msg"; fi
      }
      mapfile -t options < zfs_rootzil_disklist_var01
      prompt="Check an option to select SSD disks (again to uncheck, ENTER when done): "
      while menu && read -rp "$prompt" num && [[ "$num" ]]; do
        [[ "$num" != *[![:digit:]]* ]] &&
        (( num > 0 && num <= ${#options[@]} )) ||
        { msg="Invalid option: $num"; continue; }
        ((num--)); msg="${options[num]} was ${choices[num]:+un}checked"
        [[ "${choices[num]}" ]] && choices[num]="" || choices[num]="+"
      done
      echo
      printf "Your selected ZIL cache disk partitions are:\n"; msg=" nothing"
      for i in ${!options[@]}; do
        [[ "${choices[i]}" ]] && { printf "${YELLOW}Disk ID:${NC}  %s\n" "${options[i]}"; msg=""; } && echo $({ printf "%s" "${options[i]}"; msg=""; }) >> zpool_rootzil_disklist
      done
    echo
    echo
    if [ -s zpool_rootcache_disklist ]; then
      msg "${YELLOW}You selected the following disks for ARC or L2ARC Cache:${NC}\n${WHITE}$(cat zpool_rootcache_disklist 2>/dev/null)${NC}"
    else
      msg "${YELLOW}You selected the following disks for ARC or L2ARC Cache:\n${WHITE}None. You have NOT selected any disks!${NC}"
    fi
    echo
    if [ -s zpool_rootzil_disklist ]; then
      msg "${YELLOW}You selected the following disks for ZIL:${NC}\n${WHITE}$(cat zpool_rootzil_disklist 2>/dev/null)${NC}"
    else
      msg "${YELLOW}You selected the following disks for ZIL:\n${WHITE}None. You have NOT selected any disks!${NC}"
    fi
    echo
    read -p "Confirm your ARC or L2ARC Cache and ZIL disk selection is correct: [yes/no]?: " -r
    if [[ "$REPLY" == "y" || "$REPLY" == "Y" || "$REPLY" == "yes" || "$REPLY" == "Yes" ]]; then
      info "Success. Moving on."
      ZFS_ROOTCACHE_READY=0
      echo
      break
    else
      echo
      warn "No good. No problem. Try again."
      rm {zfs_rootcachezil_disklist_var01,zfs_rootcachezil_disklist_var02,zfs_rootzil_disklist_var01,zpool_rootcache_disklist,zpool_rootzil_disklist} 2>/dev/null
      sleep 2
      echo
    fi
    done
  else
    info "You have chosen not to set ARC or L2ARC Cache or ZIL on $HOSTNAME Proxmox OS root drives. You may choose to use dedicated SSD's for ZFS caching in the coming steps."
    ZFS_ROOTCACHE_READY=1
    fdisk -l $(fdisk -l 2>/dev/null | grep -E 'BIOS boot|EFI System'| awk '{ print $1 }' | sort | sed 's/[0-9]*//g' | awk '!seen[$0]++') | grep -Ev 'BIOS boot|EFI System|Solaris /usr & Apple ZFS' | grep -E 'Linux filesystem' | awk '{ print $1 }' > zpool_rootcacheall_disklist_var01
    for f in $(cat zpool_rootcacheall_disklist_var01 | awk '{ print $1 }' | sed 's|/dev/||')
    do read dev
      echo "$dev" "$(ls -l /dev/disk/by-id/ata* | grep -w "$f" | awk '{ print $9 }' | sed 's|/dev/disk/by-id/||')" "$(fdisk -l /dev/"$f" | grep -w "Disk /dev/"$f"" | awk '{print $3, $4}' | sed 's|,||')" "$(if [ $(cat /sys/block/"$(echo $f | sed 's/[0-9]*//g')"/queue/rotational) == 0 ];then echo "ssd"; else echo "harddisk";fi)" >> zpool_rootcacheall_disklist
    done < zpool_rootcacheall_disklist_var01
  fi
else
  ZFS_ROOTCACHE_READY=1
  fdisk -l $(fdisk -l 2>/dev/null | grep -E 'BIOS boot|EFI System'| awk '{ print $1 }' | sort | sed 's/[0-9]*//g' | awk '!seen[$0]++') | grep -Ev 'BIOS boot|EFI System|Solaris /usr & Apple ZFS' | grep -E 'Linux filesystem' | awk '{ print $1 }' > zpool_rootcacheall_disklist_var01
  for f in $(cat zpool_rootcacheall_disklist_var01 | awk '{ print $1 }' | sed 's|/dev/||')
  do read dev
    echo "$dev" "$(ls -l /dev/disk/by-id/ata* | grep -w "$f" | awk '{ print $9 }' | sed 's|/dev/disk/by-id/||')" "$(fdisk -l /dev/"$f" | grep -w "Disk /dev/"$f"" | awk '{print $3, $4}' | sed 's|,||')" "$(if [ $(cat /sys/block/"$(echo $f | sed 's/[0-9]*//g')"/queue/rotational) == 0 ];then echo "ssd"; else echo "harddisk";fi)" >> zpool_rootcacheall_disklist
  done < zpool_rootcacheall_disklist_var01
set -Eeuo pipefail
fi


# Find ZFS Pool scan disks
msg "Finding disks for zpool $POOL ..."
# create list of all disks
ls -l /dev/disk/by-id/ata* | awk '{ print $11}'  | sed 's|../../|/dev/|' | sort > zfs_disklist_var01
# add unformatted / unused disks
lsblk -r --output NAME,MOUNTPOINT | awk -F \/ '/sd/ { dsk=substr($1,1,3);dsks[dsk]+=1 } END { for ( i in dsks ) { if (dsks[i]==1) print "/dev/"i } }' >> zfs_disklist_var01
# remove all - OS & boot disks / Root ZIL disks / Root Cache disks
cat boot_disklist zpool_rootzil_disklist zpool_rootcache_disklist zpool_rootcacheall_disklist 2>/dev/null | awk '!seen[$0]++' > temp_var01
awk -F " "  'NR==FNR {a[$1];next}!($1 in a) {print $0}' temp_var01 zfs_disklist_var01 | awk '!seen[$0]++' | sort > zfs_disklist_var02
# Add Linux by-id to column 2 & Disk Size to column 3,4 & Disk Type to column 5
for f in $(cat zfs_disklist_var02 | awk '{ print $1 }' | sed 's|/dev/||')
  do read dev
    echo "$dev" "$(ls -l /dev/disk/by-id/ata* | grep -w "$f" | awk '{ print $9 }' | sed 's|/dev/disk/by-id/||')" "$(fdisk -l /dev/"$f" | grep -w "Disk /dev/"$f"" | awk '{print $3, $4}' | sed 's|,||')" "$(if [ $(cat /sys/block/"$(echo $f | sed 's/[0-9]*//g')"/queue/rotational) == 0 ];then echo "ssd"; else echo "harddisk";fi)" >> zfs_disklist_var03
done < zfs_disklist_var02
# remove any partition disks
if [ $(cat zfs_disklist_var03 | awk '{ print $1 }' | grep -c 'sd[a-z][0-9]') -gt 0 ]; then
  msg "The following disks contain existing partitions (partitions in red):\n$(cat zfs_disklist_var03 | grep -v 'sd[a-z][0-9]')\n${RED}$(cat zfs_disklist_var03 | grep 'sd[a-z][0-9]')${NC}\n\nYou can choose to either:\n  1.  (Recommended) Zap, Erase, Clean and Wipe ZFS pool disks of all partitions.\n      (Note: This results in 100% destruction of all data on the disk.)\n  2.  Select which disk partition to use."
  echo
  read -p "Proceed to Zap, Erase, Clean and Wipe disks [yes/no]?: " -r
  if [[ "$REPLY" == "y" || "$REPLY" == "Y" || "$REPLY" == "yes" || "$REPLY" == "Yes" ]]; then
    cat zfs_disklist_var03 | grep -v 'sd[a-z][0-9]' 2>/dev/null > zfs_disklist
    info "Good choice. Using whole disk in your zpool $POOL File Server."
    echo
  else
    cat zfs_disklist_var03 2>/dev/null > zfs_disklist
    info "You have chosen to use disk partitions in your zpool $POOL File Server."
    echo
  fi
fi


# Checking for ZFS pool /tank 
msg "Checking for ZFS pool /tank..." 
if [ $(zpool list $POOL > /dev/null 2>&1; echo $?) == 0 ] && [ $(cat zfs_disklist | wc -l) -ge 1 ]; then
  info "ZFS pool ${YELLOW}$POOL${NC} already exists, skipping creating ZFS pool $POOL."
  ZPOOL_TANK=0
elif [ $(zpool list $POOL > /dev/null 2>&1; echo $?) != 0 ] && [ $(cat zfs_disklist | wc -l) -ge 1 ]; then
  info "ZFS pool $POOL does NOT exist on host: ${YELLOW}$HOSTNAME${NC}.
We identified $(cat zfs_disklist | awk '$5~"harddisk"' | wc -l)x rotational hard drives and $(cat zfs_disklist | awk '$5~"ssd"' | wc -l)x SSD drives
suitable for creating ZFS pool: ${YELLOW}$POOL${NC}.
If you choose to create ZFS pool $POOL these $(cat zfs_disklist | wc -l)x drives will
be ${WHITE}erased, formatted and all existing data on the drives lost forever${NC}."
  read -p "Proceed to create ZFS pool $POOL [yes/no]?: " -r
  if [[ "$REPLY" == "y" || "$REPLY" == "Y" || "$REPLY" == "yes" || "$REPLY" == "Yes" ]]; then
    ZFSPOOL_TANK_CREATE=0
  else
    info "Not creating ZFS pool $POOL. Skipping this step."
    ZFSPOOL_TANK_CREATE=1
  fi
  ZPOOL_TANK=1
fi
echo


# Building ZFS pool disk type options list
if [ "$ZPOOL_TANK" = 1 ] && [ "$ZFSPOOL_TANK_CREATE" = 0 ]; then
while true
do
  msg "You have $(cat zfs_disklist | awk '$5~"harddisk"' | wc -l)x rotational disks and $(cat zfs_disklist | awk '$5~"ssd"' | wc -l)x SSD disks available for your ZFS pool tank.\nYou cannot combine both types of drives in a single ZFS pool.\nYou now must decide on your ZFS pool setup."
  TYPE01="${YELLOW}TYPE01${NC} - $(cat zfs_disklist | awk '$5~"harddisk"' | wc -l)x disk ZFS pool only (No ZFS cache)." >/dev/null
  TYPE02="${YELLOW}TYPE02${NC} - $(cat zfs_disklist | awk '$5~"harddisk"' | wc -l)x disk ZFS pool WITH ZFS root cache." >/dev/null
  TYPE03="${YELLOW}TYPE03${NC} - $(cat zfs_disklist | awk '$5~"harddisk"' | wc -l)x disk ZFS pool AND up to $(cat zfs_disklist | awk '$5~"ssd"' | wc -l)x SSD disk ZFS cache." >/dev/null
  TYPE04="${YELLOW}TYPE04${NC} - $(cat zfs_disklist | awk '$5~"ssd"' | wc -l)x SSD ZFS pool only (No ZFS cache)." >/dev/null
  TYPE05="${YELLOW}TYPE05${NC} - $(cat zfs_disklist | awk '$5~"ssd"' | wc -l)x SSD ZFS pool WITH ZFS root cache." >/dev/null
  TYPE06="${YELLOW}TYPE06${NC} - $(cat zfs_disklist | awk '$5~"ssd"' | wc -l)x SSD ZFS pool AND SSD disk ZFS cache." >/dev/null
  echo
  if [ $(cat zfs_disklist | awk '$5~"harddisk"' | wc -l) -ge 1 ] && [ $(cat zfs_disklist | awk '$5~"ssd"' | wc -l) == 0 ] && [ $ZFS_ROOTCACHE_READY == 1 ];then
    msg "You have $(cat zfs_disklist | awk '$5~"harddisk"' | wc -l)x rotational disks available."
    PS3="Select from the following options (entering numeric) : "
    echo
    select zpool_type in "$TYPE01"
    do
    echo
    info "You have selected: $zpool_type"
    ZPOOL_OPTIONS_TYPE=$(echo $zpool_type | sed 's/\s.*$//' | sed 's/\x1b\[[0-9;]*m//g' | sed -e 's/\(.*\)/\L\1/')
    echo
    break
    done
  elif [ $(cat zfs_disklist | awk '$5~"harddisk"' | wc -l) -ge 1 ] && [ $(cat zfs_disklist | awk '$5~"ssd"' | wc -l) == 0 ] && [ $ZFS_ROOTCACHE_READY == 0 ];then
    msg "You have $(cat zfs_disklist | awk '$5~"harddisk"' | wc -l)x rotational disks available."
    PS3="Select from the following options (entering numeric) : "
    echo
    select zpool_type in "$TYPE02"
    do
    echo
    info "You have selected: $zpool_type"
    ZPOOL_OPTIONS_TYPE=$(echo $zpool_type | sed 's/\s.*$//' | sed 's/\x1b\[[0-9;]*m//g' | sed -e 's/\(.*\)/\L\1/')
    echo
    break
    done
  elif [ $(cat zfs_disklist | awk '$5~"harddisk"' | wc -l) -ge 1 ] && [ $(cat zfs_disklist | awk '$5~"ssd"' | wc -l) -ge 1 ] && [ $ZFS_ROOTCACHE_READY == 1 ];then
    msg "You have $(cat zfs_disklist | awk '$5~"harddisk"' | wc -l)x rotational disks and $(cat zfs_disklist | awk '$5~"ssd"' | wc -l)x SSD disks available.\nRecommend: Create a ZFS Cache to boost rotational disk read & write performance: i.e TYPE03"
    PS3="Select from the following options (entering numeric) : "
    echo
    select zpool_type in "$TYPE01" "$TYPE03"
    do
    echo
    info "You have selected: $zpool_type"
    ZPOOL_OPTIONS_TYPE=$(echo $zpool_type | sed 's/\s.*$//' | sed 's/\x1b\[[0-9;]*m//g' | sed -e 's/\(.*\)/\L\1/')
    echo
    break
    done
  elif [ $(cat zfs_disklist | awk '$5~"harddisk"' | wc -l) == 0 ] && [ $(cat zfs_disklist | awk '$5~"ssd"' | wc -l) == 1 ] && [ $ZFS_ROOTCACHE_READY == 1 ];then
    msg "You have $(cat zfs_disklist | awk '$5~"ssd"' | wc -l)x SSD disks available."
    PS3="Select from the following options (entering numeric) : "
    echo
    select zpool_type in "$TYPE04"
    do
    echo
    info "You have selected: $zpool_type"
    ZPOOL_OPTIONS_TYPE=$(echo $zpool_type | sed 's/\s.*$//' | sed 's/\x1b\[[0-9;]*m//g' | sed -e 's/\(.*\)/\L\1/')
    echo
    break
    done
  elif [ $(cat zfs_disklist | awk '$5~"harddisk"' | wc -l) == 0 ] && [ $(cat zfs_disklist | awk '$5~"ssd"' | wc -l) == 1 ] && [ $ZFS_ROOTCACHE_READY = 0 ];then
    msg "You have $(cat zfs_disklist | awk '$5~"ssd"' | wc -l)x SSD disks available."
    PS3="Select from the following options (entering numeric) : "
    echo
    select zpool_type in "$TYPE05"
    do
    echo
    info "You have selected: $zpool_type"
    ZPOOL_OPTIONS_TYPE=$(echo $zpool_type | sed 's/\s.*$//' | sed 's/\x1b\[[0-9;]*m//g' | sed -e 's/\(.*\)/\L\1/')
    echo
    break
    done
  elif [ $(cat zfs_disklist | awk '$5~"harddisk"' | wc -l) == 0 ] && [ $(cat zfs_disklist | awk '$5~"ssd"' | wc -l) -ge 2 ] && [ $ZFS_ROOTCACHE_READY == 1 ];then
    msg "You have $(cat zfs_disklist | awk '$5~"ssd"' | wc -l)x SSD disks available.\nRecommend: Create a ZFS Cache to boost disk read & write performance: i.e TYPE06"
    PS3="Select from the following options (entering numeric) : "
    echo
    select zpool_type in "$TYPE04" "$TYPE06"
    do
    echo
    info "You have selected: $zpool_type"
    ZPOOL_OPTIONS_TYPE=$(echo $zpool_type | sed 's/\s.*$//' | sed 's/\x1b\[[0-9;]*m//g' | sed -e 's/\(.*\)/\L\1/')
    echo
    break
    done
  elif [ $(cat zfs_disklist | awk '$5~"harddisk"' | wc -l) == 0 ] && [ $(cat zfs_disklist | awk '$5~"ssd"' | wc -l) -ge 2 ] && [ $ZFS_ROOTCACHE_READY == 0 ];then
    msg "You have $(cat zfs_disklist | awk '$5~"ssd"' | wc -l)x SSD disks available."
    PS3="Select from the following options (entering numeric) : "
    echo
    select zpool_type in "$TYPE05"
    do
    echo
    info "You have selected: $zpool_type"
    ZPOOL_OPTIONS_TYPE=$(echo $zpool_type | sed 's/\s.*$//' | sed 's/\x1b\[[0-9;]*m//g' | sed -e 's/\(.*\)/\L\1/')
    echo
    break
    done
  fi
read -p "Confirm your selection is correct:
${YELLOW}  $zpool_type${NC} [yes/no]?: " -r
if [[ "$REPLY" == "y" || "$REPLY" == "Y" || "$REPLY" == "yes" || "$REPLY" == "Yes" ]]; then 
  break
else
  echo
  warn "No good. No problem. Try again."
  sleep 2
  echo
fi
done
fi
echo


# Create ZFS Pool disk lists
if [ "$ZPOOL_TANK" = 1 ] && [ "$ZFSPOOL_TANK_CREATE" = 0 ]; then
while true
do
  if [[ $ZPOOL_OPTIONS_TYPE == "type01" || $ZPOOL_OPTIONS_TYPE == "type02" ]];then
    msg "Creating a list of available disks for ZFS pool $POOL..."
    cat zfs_disklist | awk '$5~"harddisk"' 2>/dev/null > zpool_harddisk_disklist_var01
    msg "Please select the disks to be used in ZFS pool: ${YELLOW}$POOL${NC}."
    menu() {
      echo "Available options:"
      for i in ${!options[@]}; do
          printf "%3d%s) %s\n" $((i+1)) "${choices[i]:- }" "${options[i]}"
      done
      if [[ "$msg" ]]; then echo "$msg"; fi
    }
    mapfile -t options < zpool_harddisk_disklist_var01
    prompt="Check an option to select disk disks (again to uncheck, ENTER when done): "
    while menu && read -rp "$prompt" num && [[ "$num" ]]; do
      [[ "$num" != *[![:digit:]]* ]] &&
      (( num > 0 && num <= ${#options[@]} )) ||
      { msg="Invalid option: $num"; continue; }
      ((num--)); msg="${options[num]} was ${choices[num]:+un}checked"
      [[ "${choices[num]}" ]] && choices[num]="" || choices[num]="+"
    done
    echo
    printf "Your selected disks are:\n"; msg=" nothing"
    for i in ${!options[@]}; do
      [[ "${choices[i]}" ]] && { printf "${YELLOW}Disk ID:${NC}  %s\n" "${options[i]}"; msg=""; } && echo $({ printf "%s" "${options[i]}"; msg=""; }) >> zpool_harddisk_disklist
    done
  elif [ $ZPOOL_OPTIONS_TYPE == "type03" ];then
    msg "Creating a list of available disks for ZFS pool $POOL..."
    cat zfs_disklist | awk '$5~"harddisk"' 2>/dev/null > zpool_harddisk_disklist_var01  
    cat zfs_disklist | awk '$5~"ssd"' 2>/dev/null > zpool_cache_disklist_var01    
    msg "Please select the disks to be used in ZFS pool: ${YELLOW}$POOL${NC}."
    menu() {
      echo "Available options:"
      for i in ${!options[@]}; do 
          printf "%3d%s) %s\n" $((i+1)) "${choices[i]:- }" "${options[i]}"
      done
      if [[ "$msg" ]]; then echo "$msg"; fi
    }
    mapfile -t options < zpool_harddisk_disklist_var01
    prompt="Check an option to select disk disks (again to uncheck, ENTER when done): "
    while menu && read -rp "$prompt" num && [[ "$num" ]]; do
      [[ "$num" != *[![:digit:]]* ]] &&
      (( num > 0 && num <= ${#options[@]} )) ||
      { msg="Invalid option: $num"; continue; }
      ((num--)); msg="${options[num]} was ${choices[num]:+un}checked"
      [[ "${choices[num]}" ]] && choices[num]="" || choices[num]="+"
    done
    echo
    printf "Your selected disk disks are:\n"; msg=" nothing"
    for i in ${!options[@]}; do
      [[ "${choices[i]}" ]] && { printf "${YELLOW}Disk ID:${NC}  %s\n" "${options[i]}"; msg=""; } && echo $({ printf "%s" "${options[i]}"; msg=""; }) >> zpool_harddisk_disklist
    done
    echo   
    if [ $(cat zpool_cache_disklist_var01 | wc -l) -ge 1 ] && [ $ZFS_ROOTCACHE_READY = 1 ]; then
      msg "Creating a list of available SSD disks for ARC or L2ARC cache and ZIL..."
      msg "There are two different SSD caches that a ZFS pool can make use of:\n  1.  ZFS Intent Log, or ZIL, to buffer WRITE operations.\n  2.  ARC and L2ARC cache which are meant for READ operations.\nIn the next steps you will asked to select disks which will be partitioned for ZIL and ARC or L2ARC cache.\nThese disks will be erased and wiped of all data.\n\nYou have 2x or more SSD disks available for ARC or L2ARC cache and ZIL. Your options are: \n1)  ${YELLOW}Standard Cache${NC}: Select 1x SSD cache disk only. No ARC, L2ARC or ZIL disk redundancy.\n2)  ${YELLOW}Accelerated Cache${NC}: Select 2x SSD cache disks. ARC or L2ARC cache set to Raid0 (stripe) and ZIL set to Raid1 (mirror).\nThere is no need to select more than 2x SSD disks!"
      msg "Please select the SSD disks to be used for ARC or L2ARC cache and ZIL:"
      menu() {
        echo "Available options:"
        for i in ${!options[@]}; do 
            printf "%3d%s) %s\n" $((i+1)) "${choices[i]:- }" "${options[i]}"
        done
        if [[ "$msg" ]]; then echo "$msg"; fi
      }
      mapfile -t options < zpool_cache_disklist_var01
      prompt="Check an option to select SSD disks (again to uncheck, ENTER when done): "
      while menu && read -rp "$prompt" num && [[ "$num" ]]; do
        [[ "$num" != *[![:digit:]]* ]] &&
        (( num > 0 && num <= ${#options[@]} )) ||
        { msg="Invalid option: $num"; continue; }
        ((num--)); msg="${options[num]} was ${choices[num]:+un}checked"
        [[ "${choices[num]}" ]] && choices[num]="" || choices[num]="+"
      done
      echo
      printf "Your selected SSD cache disks are:\n"; msg=" nothing"
      for i in ${!options[@]}; do
        [[ "${choices[i]}" ]] && { printf "${YELLOW}Disk ID:${NC}  %s\n" "${options[i]}"; msg=""; } && echo $({ printf "%s" "${options[i]}"; msg=""; }) >> zpool_cache_disklist
      done
    elif [ $ZFS_ROOTCACHE_READY = 0 ]; then
      msg "You have already selected Root File System partitions for ARC or L2ARC Cache:\n${WHITE}$(cat zpool_rootcache_disklist 2>/dev/null)${NC}"
      msg "You have already selected Root File System partitions for ZIL:\n${WHITE}$(cat zpool_rootzil_disklist 2>/dev/null)${NC}"
    fi
  elif [[ $ZPOOL_OPTIONS_TYPE == "type04" || $ZPOOL_OPTIONS_TYPE == "type05" ]];then
    msg "Creating a list of available SSD disks for ZFS pool $POOL..."
    cat zfs_disklist | awk '$5~"ssd"' 2>/dev/null > zpool_ssd_disklist_var01
    msg "Please select the SSD disks to be used in ZFS pool: ${YELLOW}$POOL${NC}."
    menu() {
      echo "Available options:"
      for i in ${!options[@]}; do 
          printf "%3d%s) %s\n" $((i+1)) "${choices[i]:- }" "${options[i]}"
      done
      if [[ "$msg" ]]; then echo "$msg"; fi
    }
    mapfile -t options < zpool_ssd_disklist_var01
    prompt="Check an option to select SSD disks (again to uncheck, ENTER when done): "
    while menu && read -rp "$prompt" num && [[ "$num" ]]; do
      [[ "$num" != *[![:digit:]]* ]] &&
      (( num > 0 && num <= ${#options[@]} )) ||
      { msg="Invalid option: $num"; continue; }
      ((num--)); msg="${options[num]} was ${choices[num]:+un}checked"
      [[ "${choices[num]}" ]] && choices[num]="" || choices[num]="+"
    done
    echo
    printf "Your selected SSD disks are:\n"; msg=" nothing"
    for i in ${!options[@]}; do
      [[ "${choices[i]}" ]] && { printf "${YELLOW}Disk ID:${NC}  %s\n" "${options[i]}"; msg=""; } && echo $({ printf "%s" "${options[i]}"; msg=""; }) >> zpool_ssd_disklist
    done   
  elif [ $ZPOOL_OPTIONS_TYPE == "type06" ];then
    msg "Creating a list of available SSD disks for ZFS pool $POOL..."
    cat zfs_disklist | awk '$5~"ssd"' > zpool_ssd_disklist_var01
    if [ $ZFS_ROOTCACHE_READY = 1 ]; then
      msg "Please select the SSD disks to be used in ZFS pool: ${YELLOW}$POOL${NC}.
      Do not select all SSD disks. Leave one or two SSD disks unselected for ZFS cache."
    elif [ $ZFS_ROOTCACHE_READY = 0 ]; then
      msg "Please select the SSD disks to be used in ZFS pool: ${YELLOW}$POOL${NC}."
    fi
    menu() {
      echo "Available options:"
      for i in ${!options[@]}; do 
          printf "%3d%s) %s\n" $((i+1)) "${choices[i]:- }" "${options[i]}"
      done
      if [[ "$msg" ]]; then echo "$msg"; fi
    }
    mapfile -t options < zpool_ssd_disklist_var01
    prompt="Check an option to select SSD disks (again to uncheck, ENTER when done): "
    while menu && read -rp "$prompt" num && [[ "$num" ]]; do
      [[ "$num" != *[![:digit:]]* ]] &&
      (( num > 0 && num <= ${#options[@]} )) ||
      { msg="Invalid option: $num"; continue; }
      ((num--)); msg="${options[num]} was ${choices[num]:+un}checked"
      [[ "${choices[num]}" ]] && choices[num]="" || choices[num]="+"
    done
    echo
    printf "Your selected SSD disks are:\n"; msg=" nothing"
    for i in ${!options[@]}; do
      [[ "${choices[i]}" ]] && { printf "${YELLOW}Disk ID:${NC}  %s\n" "${options[i]}"; msg=""; } && echo $({ printf "%s" "${options[i]}"; msg=""; }) >> zpool_ssd_disklist
    done
    echo
    if [ $(cat zpool_cache_disklist_var01 | wc -l) -ge 1 ] && [ $ZFS_ROOTCACHE_READY = 1 ]; then
      awk -F " "  'NR==FNR {a[$1];next}!($1 in a) {print $0}' zpool_ssd_disklist zpool_ssd_disklist_var01 | awk '!seen[$0]++' | sort > zpool_cache_disklist_var01
      msg "Creating a list of available SSD disks for ARC or L2ARC cache and ZIL..."
      msg "There are two different SSD caches that a ZFS pool can make use of:\n  1.  ZFS Intent Log, or ZIL, to buffer WRITE operations.\n  2.  ARC and L2ARC cache which are meant for READ operations.\nIn the next steps you will asked to select disks which will be partitioned for ZIL and ARC or L2ARC cache.\nThese disks will be erased and wiped of all data.\n\n
      You have 2x or more SSD disks available for ARC or L2ARC cache and ZIL. Your options are: \n1)  ${YELLOW}Standard Cache${NC}: Select 1x SSD cache disk only. No ARC,L2ARC or ZIL disk redundancy.\n2)  ${YELLOW}Accelerated Cache${NC}: Select 2x SSD cache disks. ARC or L2ARC cache set to Raid0 (stripe) and ZIL set to Raid1 (mirror).\n
      No need to select more than 2x SSD disks!"
      msg "Please select the SSD disks to be used for ARC or L2ARC cache and ZIL:"
    menu() {
      echo "Available options:"
      for i in ${!options[@]}; do 
          printf "%3d%s) %s\n" $((i+1)) "${choices[i]:- }" "${options[i]}"
      done
      if [[ "$msg" ]]; then echo "$msg"; fi
    }
    mapfile -t options < zpool_cache_disklist_var01
    prompt="Check an option to select SSD disks (again to uncheck, ENTER when done): "
    while menu && read -rp "$prompt" num && [[ "$num" ]]; do
      [[ "$num" != *[![:digit:]]* ]] &&
      (( num > 0 && num <= ${#options[@]} )) ||
      { msg="Invalid option: $num"; continue; }
      ((num--)); msg="${options[num]} was ${choices[num]:+un}checked"
      [[ "${choices[num]}" ]] && choices[num]="" || choices[num]="+"
    done
    echo
    printf "Your selected SSD cache disks are:\n"; msg=" nothing"
    for i in ${!options[@]}; do
      [[ "${choices[i]}" ]] && { printf "${YELLOW}Disk ID:${NC}  %s\n" "${options[i]}"; msg=""; } && echo $({ printf "%s" "${options[i]}"; msg=""; }) >> zpool_cache_disklist
    done
    elif [ $ZFS_ROOTCACHE_READY = 0 ]; then
      msg "You have already selected Root File System partitions for ARC or L2ARC Cache:\n${WHITE}$(cat zpool_rootcache_disklist 2>/dev/null)${NC}"
      msg "You have already selected Root File System partitions for ZIL:\n${WHITE}$(cat zpool_rootzil_disklist 2>/dev/null)${NC}"
    fi
  fi
echo
echo
if [ -s zpool_harddisk_disklist ] || [ -s zpool_ssd_disklist ]; then
  msg "Your ZFS Pool disk selection is:
${YELLOW}ZFS Pool Disk ID:${NC}
${WHITE}$(cat zpool_harddisk_disklist zpool_ssd_disklist 2>/dev/null)${NC}"
else
  msg "Your final ZFS Pool disk selection is:
${YELLOW}ZFS Pool Disk ID:${NC}
${WHITE}You have NOT selected any disks!${NC}"
fi
if [ -s zpool_cache_disklist ]; then
  echo
  msg "Your ZFS cache setup is:"
  msg "${YELLOW}ARC, L2ARC and ZIL SSD Cache Disk ID:${NC} (whole disks)
${WHITE}$(cat zpool_cache_disklist 2>/dev/null)${NC}"
fi
if [ $ZFS_ROOTCACHE_READY = 0 ]; then
  echo
  msg "Your ZFS cache setup is:"
  msg "${YELLOW}Root File System Partitioned for ARC or L2ARC. Disk ID:${NC}
${WHITE}$(cat zpool_rootcache_disklist 2>/dev/null)${NC}"
  msg "${YELLOW}Root File System Partitioned for ZIL. Disk ID:${NC}
${WHITE}$(cat zpool_rootzil_disklist 2>/dev/null)${NC}"
fi
echo
read -p "Confirm your zpool disk selection is correct: [yes/no]?: " -r
if [[ "$REPLY" == "y" || "$REPLY" == "Y" || "$REPLY" == "yes" || "$REPLY" == "Yes" ]]; then 
  break
else
  echo
  warn "No good. No problem. Try again."
  rm {zpool_harddisk_disklist_var01,zpool_harddisk_disklist,zpool_ssd_disklist_var01,zpool_ssd_disklist,zpool_cache_disklist_var01,zpool_cache_disklist} 2>/dev/null
  sleep 2
  echo
fi
done
fi
echo


# Checking for ZFS pool /tank Raid level options
if [ "$ZPOOL_TANK" = 1 ] && [ "$ZFSPOOL_TANK_CREATE" = 0 ]; then
while true; do
  msg "Checking available Raid level options for your ZFS pool /$POOL..."
  echo
  RAID0="${YELLOW}RAID0${NC} - Also called “striping”. No redundancy, so the failure of a single drive makes the volume unusable." >/dev/null
  RAID1="${YELLOW}RAID1${NC} - Also called “mirroring”. Data is written identically to all disks. The resulting capacity is that of a single disk." >/dev/null
  RAID10="${YELLOW}RAID10${NC} - A combination of RAID0 and RAID1. Requires at least 4 disks." >/dev/null
  RAIDZ1="${YELLOW}RAIDZ1${NC} - A variation on RAID-5, single parity. Requires at least 3 disks." >/dev/null
  RAIDZ2="${YELLOW}RAIDZ2${NC} - A variation on RAID-5, double parity. Requires at least 4 disks." >/dev/null
  RAIDZ3="${YELLOW}RAIDZ3${NC} - A variation on RAID-5, triple parity. Requires at least 5 disks." >/dev/null
  if [ $(cat zpool_harddisk_disklist 2>/dev/null | wc -l) = 1 ] || [ $(cat zpool_ssd_disklist 2>/dev/null | wc -l) = 1 ]; then
    msg "Raid type options for ${WHITE}$(( $(cat zpool_harddisk_disklist 2>/dev/null | wc -l) + $(cat zpool_ssd_disklist 2>/dev/null | wc -l) ))x${NC} disks are:"
    PS3="Select a Raid type for your ZFS pool /$POOL (entering numeric) : "
    echo
    select raid_type in "$RAID0"
    do
    echo
    msg "You have selected: $(echo $raid_type | sed 's/\s.*$//')"
    ZPOOL_RAID_TYPE=$(echo $raid_type | sed 's/\s.*$//' | sed 's/\x1b\[[0-9;]*m//g' | sed -e 's/\(.*\)/\L\1/')
    echo
    break
    done
  elif [ $(cat zpool_harddisk_disklist 2>/dev/null | wc -l) = 2 ] || [ $(cat zpool_ssd_disklist 2>/dev/null | wc -l) = 2 ]; then
    msg "Raid type options for ${WHITE}$(( $(cat zpool_harddisk_disklist 2>/dev/null | wc -l) + $(cat zpool_ssd_disklist 2>/dev/null | wc -l) ))x${NC} disks are (Recommend RAID1):"
    PS3="Select the Raid type for your ZFS pool /$POOL (entering numeric) : "
    echo
    select raid_type in "$RAID0" "$RAID1"
    do
    echo
    msg "You have selected: $(echo $raid_type | sed 's/\s.*$//')"
    ZPOOL_RAID_TYPE=$(echo $raid_type | sed 's/\s.*$//' | sed 's/\x1b\[[0-9;]*m//g' | sed -e 's/\(.*\)/\L\1/')
    echo
    break
    done
  elif [ $(cat zpool_harddisk_disklist 2>/dev/null | wc -l) = 3 ] || [ $(cat zpool_ssd_disklist 2>/dev/null | wc -l) = 3 ]; then
    msg "Raid type options for ${WHITE}$(( $(cat zpool_harddisk_disklist 2>/dev/null | wc -l) + $(cat zpool_ssd_disklist 2>/dev/null | wc -l) ))x${NC} disks are(Recommend RAIDZ1):"
    PS3="Select the Raid type for your ZFS pool /$POOL (entering numeric) : "
    echo
    select raid_type in "$RAID0" "$RAID1" "$RAIDZ1"
    do
    echo
    msg "You have selected: $(echo $raid_type | sed 's/\s.*$//')"
    ZPOOL_RAID_TYPE=$(echo $raid_type | sed 's/\s.*$//' | sed 's/\x1b\[[0-9;]*m//g' | sed -e 's/\(.*\)/\L\1/')
    echo
    break
    done
  elif [ $(cat zpool_harddisk_disklist 2>/dev/null | wc -l) = 4 ] || [ $(cat zpool_ssd_disklist 2>/dev/null | wc -l) = 4 ]; then
    msg "Raid type options for ${WHITE}$(( $(cat zpool_harddisk_disklist 2>/dev/null | wc -l) + $(cat zpool_ssd_disklist 2>/dev/null | wc -l) ))x${NC} disks are (Recommend RAIDZ1):"
    PS3="Select the Raid type for your ZFS pool /$POOL (entering numeric) : "
    echo
    select raid_type in "$RAID0" "$RAID1" "$RAID10" "$RAIDZ1" "$RAIDZ2"
    do
    echo
    msg "You have selected: $(echo $raid_type | sed 's/\s.*$//')"
    ZPOOL_RAID_TYPE=$(echo $raid_type | sed 's/\s.*$//' | sed 's/\x1b\[[0-9;]*m//g' | sed -e 's/\(.*\)/\L\1/')
    echo
    break
    done
  elif [ $(cat zpool_harddisk_disklist 2>/dev/null | wc -l) -ge 5 ] || [ $(cat zpool_ssd_disklist 2>/dev/null | wc -l) -ge 5 ]; then
    msg "Raid type options for ${WHITE}$(( $(cat zpool_harddisk_disklist 2>/dev/null | wc -l) + $(cat zpool_ssd_disklist 2>/dev/null | wc -l) ))x${NC} disks are (Recommend RAIDZ2):"
    PS3="Select the Raid type for your ZFS pool /$POOL (entering numeric) : "
    echo
    select raid_type in "$RAID0" "$RAID1" "$RAID10" "$RAIDZ1" "$RAIDZ2" "$RAIDZ3"
    do
    echo
    msg "You have selected: $(echo $raid_type | sed 's/\s.*$//')"
    ZPOOL_RAID_TYPE=$(echo $raid_type | sed 's/\s.*$//' | sed 's/\x1b\[[0-9;]*m//g' | sed -e 's/\(.*\)/\L\1/')
    echo
    break
    done
  fi
read -p "Confirm your ZFS pool raid type is correct: [yes/no]?: " -r
if [[ "$REPLY" == "y" || "$REPLY" == "Y" || "$REPLY" == "yes" || "$REPLY" == "Yes" ]]; then 
  break
else
  echo
  warn "No good. No problem. Try again."
  sleep 2
  echo
fi
done
fi
echo

    
# Erase / Wipe ZFS pool disks
if [ "$ZPOOL_TANK" = 1 ] && [ "$ZFSPOOL_TANK_CREATE" = 0 ]; then
  msg "Zapping, Erasing, Cleaning and Wiping ZFS pool disks..."
  cat zpool_harddisk_disklist 2>/dev/null | awk '{print $1}' >> zpool_disklist_erase_input
  cat zpool_ssd_disklist 2>/dev/null | awk '{print $1}' >> zpool_disklist_erase_input
  cat zpool_cache_disklist 2>/dev/null | awk '{print $1}' >> zpool_disklist_erase_input
  while read SELECTED_DEVICE; do
    sgdisk --zap $SELECTED_DEVICE  >/dev/null 2>&1
    info "SGDISK - zapped (destroyed) the GPT data structures on device: $SELECTED_DEVICE"
    dd if=/dev/zero of=$SELECTED_DEVICE count=1 bs=512 conv=notrunc 2>/dev/null
    info "DD - cleaned & wiped device: $SELECTED_DEVICE"
    wipefs --all --force $SELECTED_DEVICE  >/dev/null 2>&1
    info "wipefs - wiped device: $SELECTED_DEVICE"
  done < zpool_disklist_erase_input # file listing of disks to erase
fi
echo


# Create ZFS Pool Tank
if [ "$ZPOOL_TANK" = 1 ] && [ "$ZFSPOOL_TANK_CREATE" = 0 ]; then
  if [ $ZPOOL_RAID_TYPE == "raid0" ]; then
    msg "Creating ZFS pool $POOL. Raid type: Raid-0..."
    zpool create -f -o ashift=12 $POOL $(cat zpool_harddisk_disklist zpool_ssd_disklist 2>/dev/null | awk '{print $2}' ORS=' ' | sed 's/ *$//')
  elif [ $ZPOOL_RAID_TYPE == "raid1" ]; then
    msg "Creating ZFS pool $POOL. Raid type: Raid-1..."
    zpool create -f -o ashift=12 $POOL $(cat zpool_harddisk_disklist zpool_ssd_disklist 2>/dev/null | awk '{print $2}' ORS=' ' | sed 's/ *$//' | sed 's/^/mirror /')   
  elif [ $ZPOOL_RAID_TYPE == "raid10" ]; then
    msg "Creating ZFS pool $POOL. Raid type: Raid-10..."
    zpool create -f -o ashift=12 $POOL $(cat zpool_harddisk_disklist zpool_ssd_disklist 2>/dev/null | awk '{print $2}' ORS=' ' | sed 's/ *$//' | sed '-es/ / mirror /'{1000..1..2} | sed 's/^/mirror /')   
  elif [ $ZPOOL_RAID_TYPE == "raidz1" ]; then
    msg "Creating ZFS pool $POOL. Raid type: Raid-Z1..."
    zpool create -f -o ashift=12 $POOL raidz1 $(cat zpool_harddisk_disklist zpool_ssd_disklist 2>/dev/null | awk '{print $2}' ORS=' ' | sed 's/ *$//')
  elif [ $ZPOOL_RAID_TYPE == "raidz2" ]; then
    msg "Creating  ZFS pool $POOL. Raid type: Raid-Z2..."
    zpool create -f -o ashift=12 $POOL raidz2 $(cat zpool_harddisk_disklist zpool_ssd_disklist 2>/dev/null | awk '{print $2}' ORS=' ' | sed 's/ *$//')
  fi
fi
echo


# Create ZFS Root Cache
if [ $ZFS_ROOTCACHE_READY = 0 ] && [ -s zpool_rootcache_disklist ] && [ -s zpool_rootzil_disklist ]; then
  msg "Creating ZFS pool cache..."
  cat zpool_rootzil_disklist | awk '{ print $2 }' | sed 's/^/\/dev\/disk\/by-id\//' | awk '{print}' ORS=' ' | sed '$s/.$//' | sed 's/^/mirror /' > zpool_cache_zil_partitioned_disklist
  zpool add $POOL log $(cat zpool_cache_zil_partitioned_disklist)
  info "ZIL cache completed:\n  1.  $(cat zpool_rootzil_disklist | wc -l)x disks Raid1 (mirror)."
  cat zpool_rootcache_disklist | awk '{ print $2 }' | sed 's/^/\/dev\/disk\/by-id\//' | awk '{print}' ORS=' ' | sed '$s/.$//' > zpool_cache_arc_partitioned_disklist
  zpool add $POOL cache $(cat zpool_cache_arc_partitioned_disklist)
  info "ARC cache completed:\n  1.  $(cat zpool_rootcache_disklist | wc -l)x disks Raid0 (stripe)."
  echo
fi


# Create ZFS Pool Cache - whole disk
if [ "$ZPOOL_TANK" = 1 ] && [ "$ZFSPOOL_TANK_CREATE" = 0 ] && [ -s zpool_cache_disklist ] && [ "$ZFS_ROOTCACHE_READY" = 1 ] && [[ "$ZPOOL_OPTIONS_TYPE" = "type02" || "$ZPOOL_OPTIONS_TYPE" =  "type04" ]]; then
  msg "Calculating ARC or L2ARC cache and ZIL disk partition sizes..."
  msg "You have allocated $(cat zpool_cache_disklist 2>/dev/null | wc -l)x SSD disk for ZFS cache partitioning.\nThe maximum size of a ZIL log device should be about half the size of your hosts ${YELLOW}$(grep MemTotal /proc/meminfo | awk '{printf "%.0fGB\n", $2/1024/1024}')${NC} installed physical RAM memory BUT not less than our ${YELLOW}default 8GB${NC}.\nThe size of ARC or L2ARC cache should be not less than our ${YELLOW}default 64GB${NC} but could be the remaining size of your ZFS cache disk.\n\nYou have allocated the following $(cat zpool_cache_disklist 2>/dev/null | wc -l)x SSD disks for cache:\n${WHITE}$(cat zpool_cache_disklist 2>/dev/null)${NC}\n\nThe system will automatically calculate the best partition sizes for you. You can accept the suggested values by pressing ENTER on your keyboard.\nOr overwrite the suggested value by typing in your own value and press ENTER to accept/continue."
  echo
  if [ $(grep MemTotal /proc/meminfo | awk '{printf "%.0f\n", $2/1024/1024/2}') -le 8 ]; then
    ZIL_VAR_01=8
  else
    ZIL_VAR_01="$(grep MemTotal /proc/meminfo | awk '{printf "%.0f\n", $2/1024/1024/2}')"
  fi
  while true; do
    read -p "Enter the ZIL partition size (GB): " -e -i $ZIL_VAR_01 ZIL_VAR_02
    if [ $ZIL_VAR_02 -le $(( $(grep MemTotal /proc/meminfo | awk '{printf "%.0f\n", $2/1024/1024}') / 2 )) ] && [ $ZIL_VAR_02 -ge 8 ]; then
      info "Good ZIL Sizing. ZIL partition size is set: ${YELLOW}"$ZIL_VAR_02"GB${NC}."
      echo
      break
    elif [ $ZIL_VAR_02 -lt $(( $(grep MemTotal /proc/meminfo | awk '{printf "%.0f\n", $2/1024/1024}') / 2  )) ] && [ $ZIL_VAR_02 -lt 8 ]; then
      warn "There are problems with your input:
      1. A "$ZIL_VAR_02"GB partition size is less than 50% of your $(grep MemTotal /proc/meminfo | awk '{printf "%.0f\n", $2/1024/1024}')GB RAM.
      2. A "$ZIL_VAR_02"GB partition size is smaller than the default 8GB minimum."
      read -p "Do you want to accept a non-standard "$ZIL_VAR_02"GB partition size : [yes/no]?: " -r
      if [[ "$REPLY" == "y" || "$REPLY" == "Y" || "$REPLY" == "yes" || "$REPLY" == "Yes" ]]; then
        info "ZIL partition size is set: ${YELLOW}"$ZIL_VAR_02"GB${NC}."
        break
      else
        warn "No good. No problem. Try again."
      fi
      echo
    elif [ $ZIL_VAR_02 -gt $(( $(grep MemTotal /proc/meminfo | awk '{printf "%.0f\n", $2/1024/1024}') / 2  )) ] && [ $ZIL_VAR_02 -lt $(( $(grep MemTotal /proc/meminfo | awk '{printf "%.0f\n", $2/1024/1024}')  )) ] && [ $ZIL_VAR_02 -gt 8 ]; then
      warn "There are problems with your input:
      1. Your "$ZIL_VAR_02"GB partition size input exceeds 50% of your installed $(grep MemTotal /proc/meminfo | awk '{printf "%.0f\n", $2/1024/1024}')GB of RAM memory.
      2. Your "$ZIL_VAR_02"GB partition size input is unnecessarily larger than the default 8GB minimum."
      read -p "Do you want to accept a non-standard "$ZIL_VAR_02"GB partition size : [yes/no]?: " -r
      if [[ "$REPLY" == "y" || "$REPLY" == "Y" || "$REPLY" == "yes" || "$REPLY" == "Yes" ]]; then
        info "ZIL partition size is set: ${YELLOW}"$ZIL_VAR_02"GB${NC}."
        break
      else
        warn "No good. No problem. Try again."
      fi
      echo
    elif [ $ZIL_VAR_02 -gt $(( $(grep MemTotal /proc/meminfo | awk '{printf "%.0f\n", $2/1024/1024}') )) ] && [ $ZIL_VAR_02 -gt 8 ]; then
      warn "There are problems with your input:
      1. This is a BAD idea! A "$ZIL_VAR_02"GB partition size exceeds your total installed $(grep MemTotal /proc/meminfo | awk '{printf "%.0f\n", $2/1024/1024}')GB of RAM.
      2. And a "$ZIL_VAR_02"GB partition size is much larger than the default 8GB minimum."
      read -p "Do you want to accept a non-standard "$ZIL_VAR_02"GB partition size : [yes/no]?: " -r
      if [[ "$REPLY" == "y" || "$REPLY" == "Y" || "$REPLY" == "yes" || "$REPLY" == "Yes" ]]; then
        info "ZIL partition size is set: ${YELLOW}"$ZIL_VAR_02"GB${NC}."
        break
      else
        warn "No good. No problem. Try again."
      fi
      echo
    fi
  done
  if [ 64 -le $(( $(cat zpool_cache_disklist | sort -k 3 | awk 'NR==1{print $3}' | awk '{print ($0-int($0)<0.499)?int($0):int($0)+1}') * 9/10 - $ZIL_VAR_02 )) ]; then
    ARC_VAR_01=64
  else
    ARC_VAR_01=$(( $(cat zpool_cache_disklist | sort -k 3 | awk 'NR==1{print $3}' | awk '{print ($0-int($0)<0.499)?int($0):int($0)+1}') * 9/10 - $ZIL_VAR_02 ))
  fi
  while true; do
    read -p "Enter the ARC or L2ARC partition size (GB): " -e -i $ARC_VAR_01 ARC_VAR_02
    if [ $ARC_VAR_02 -le $(( $(cat zpool_cache_disklist | sort -k 3 | awk 'NR==1{print $3}' | awk '{print ($0-int($0)<0.499)?int($0):int($0)+1}') * 9/10 - $ZIL_VAR_01 )) ] && [ $ARC_VAR_02 -ge 64 ]; then
      info "ARC or L2ARC partition size is set: ${YELLOW}"$ARC_VAR_02"GB${NC}."
      echo
      break
    elif [ $ARC_VAR_02 -gt $(( $(cat zpool_cache_disklist | sort -k 3 | awk 'NR==1{print $3}' | awk '{print ($0-int($0)<0.499)?int($0):int($0)+1}') * 9/10 - $ZIL_VAR_01 )) ]; then
      warn "There are problems with your input:
      1)  Your "$ARC_VAR_02"GB partition size exceeds available SSD disk space.
      Try again..."
      echo
    elif [ $ARC_VAR_02 -lt 64 ]; then
      warn "There are problems with your input:
      1) Your "$ARC_VAR_02"GB partition size is smaller than the default 64GB minimum. You have "$(( $(cat zpool_cache_disklist | sort -k 3 | awk 'NR==1{print $3}' | awk '{print ($0-int($0)<0.499)?int($0):int($0)+1}') * 9/10 - $ZIL_VAR_02 ))"GB of free disk space available for this task."
      read -p "Do you want to accept a non-standard "$ARC_VAR_02"GB partition size : [yes/no]?: " -r
      if [[ "$REPLY" == "y" || "$REPLY" == "Y" || "$REPLY" == "yes" || "$REPLY" == "Yes" ]]; then
        info "ARC or L2ARC partition size is set: ${YELLOW}"$ARC_VAR_02"GB${NC}."
        break
      else
        warn "No good. No problem. Try again."
      fi
      echo
    fi
  done
  ZIL_SIZE="$(( ($ZIL_VAR_02 * 1073741824)/512 ))"
  ARC_SIZE="$(( ($ARC_VAR_02 * 1073741824)/512 ))"
  # Partitioning ZFS cache disks
  msg "Partitioning the ZFS cache disks..."
  cat zpool_cache_disklist 2>/dev/null | awk '{print $1}' > zpool_cache_disklist_partition_input
  while read SELECTED_DEVICE; do
    echo 'label: gpt' | sfdisk $SELECTED_DEVICE
    info "GPT labelled: $SELECTED_DEVICE"
    sfdisk --quiet --wipe=always --force $SELECTED_DEVICE <<-EOF
    ,$ZIL_SIZE
    ,$ARC_SIZE
EOF
    info "Partitioning complete for: $SELECTED_DEVICE"
  done < zpool_cache_disklist_partition_input # file listing of disks to erase
  echo
  # Creating ZFS Cache
  msg "Creating ZFS pool cache..."
  for f in $(cat zpool_cache_disklist_partition_input | awk '{ print $1 }' | sed 's|/dev/||')
    do read
      echo "$(fdisk -l /dev/"$f" | grep '^/dev' | cut -d' ' -f1)" >> zpool_cache_partitioned_disklist_var01
  done < zpool_cache_disklist_partition_input
  for f in $(cat zpool_cache_partitioned_disklist_var01 | awk '{ print $1 }' | sed 's|/dev/||')
    do read dev
      echo "$dev" "$(ls -l /dev/disk/by-id/ata* | grep -w "$f" | awk '{ print $9 }' | sed 's|/dev/disk/by-id/||')" "$(fdisk -l /dev/"$f" | grep -w "Disk /dev/"$f"" | awk '{print $3, $4}' | sed 's|,||')" "$(if [ $(cat /sys/block/"$(echo $f | sed 's/[0-9]*//g')"/queue/rotational) == 0 ];then echo "ssd"; else echo "harddisk";fi)" >> zpool_cache_partitioned_disklist_var02
  done < zpool_cache_partitioned_disklist_var01
  if [ $(cat zpool_cache_partitioned_disklist_var02 | grep -w "$ZIL_VAR_02 GiB" | wc -l) -le 3 ]; then
    cat zpool_cache_partitioned_disklist_var02 | grep -w "$ZIL_VAR_02 GiB" | awk '{ print $2 }' | sed 's/^/\/dev\/disk\/by-id\//' | awk '{print}' ORS=' ' | sed '$s/.$//' | sed 's/^/mirror /' > zpool_cache_zil_partitioned_disklist
    zpool add $POOL log $(cat zpool_cache_zil_partitioned_disklist)
    info "ZIL cache completed:\n  1.  $(cat zpool_cache_zil_partitioned_disklist | wc -l)x disk Raid1 (mirror only)."
    echo
  elif [ $(cat zpool_cache_partitioned_disklist_var02 | grep -w "$ZIL_VAR_02 GiB" | wc -l) -ge 4 ]; then
    count=$(cat zpool_cache_partitioned_disklist_var02 | grep -w "$ZIL_VAR_02 GiB" | wc -l)
    if [ "$((count% 2))" -eq 0 ]; then
      cat zpool_cache_partitioned_disklist_var02 | grep -w "$ZIL_VAR_02 GiB" | awk '{ print $2 }' | sed 's/^/\/dev\/disk\/by-id\//' | awk '{print}' ORS=' ' | sed '$s/.$//' | sed '-es/ / mirror /'{1000..1..2} | sed 's/^/mirror /' > zpool_cache_zil_partitioned_disklist
      zpool add $POOL log $(cat zpool_cache_zil_partitioned_disklist)
      info "ZIL cache completed:\n  1.  $(( $(cat zpool_cache_zil_partitioned_disklist | wc -l) / 2 ))x disk Raid0 (stripe).\n  2.  $(( $(cat zpool_cache_zil_partitioned_disklist | wc -l) / 2 ))x disk Raid1 (mirror)."
      echo
    else
      cat zpool_cache_partitioned_disklist_var02 | grep -w "$ZIL_VAR_02 GiB" | sed '$ d' | awk '{ print $2 }' | sed 's/^/\/dev\/disk\/by-id\//' | awk '{print}' ORS=' ' | sed '$s/.$//' | sed '-es/ / mirror /'{1000..1..2} | sed 's/^/mirror /' > zpool_cache_zil_partitioned_disklist
      zpool add $POOL log $(cat zpool_cache_zil_partitioned_disklist)
      info "ZIL cache completed:\n  1.  $(( $(cat zpool_cache_zil_partitioned_disklist | wc -l) / 2 ))x disk Raid0 (stripe).\n  1.  $(( $(cat zpool_cache_zil_partitioned_disklist | wc -l) / 2 ))x disk Raid1 (mirror)."
      echo
    fi
  fi
  if [ $(cat zpool_cache_partitioned_disklist_var02 | grep -w "$ARC_VAR_02 GiB" | wc -l) -le 3 ]; then
    cat zpool_cache_partitioned_disklist_var02 | grep -w "$ARC_VAR_02 GiB" | awk '{ print $2 }' | sed 's/^/\/dev\/disk\/by-id\//' | awk '{print}' ORS=' ' | sed '$s/.$//' > zpool_cache_arc_partitioned_disklist
    zpool add $POOL cache $(cat zpool_cache_arc_partitioned_disklist)
    info "ARC cache completed:\n  1.  $(cat zpool_cache_arc_partitioned_disklist | wc -l)x disk Raid0 (stripe only)."
    echo
  elif [ $(cat zpool_cache_partitioned_disklist_var02 | grep -w "$ARC_VAR_02 GiB" | wc -l) -ge 4 ]; then
    count=$(cat zpool_cache_partitioned_disklist_var02 | grep -w "$ARC_VAR_02 GiB" | wc -l)
    if [ "$((count% 2))" -eq 0 ]; then
      cat zpool_cache_partitioned_disklist_var02 | grep -w "$ARC_VAR_02 GiB" | awk '{ print $2 }' | sed 's/^/\/dev\/disk\/by-id\//' | awk '{print}' ORS=' ' | sed '$s/.$//' | sed '-es/ / mirror /'{1000..1..2} | sed 's/^/mirror /' > zpool_cache_arc_partitioned_disklist
      zpool add $POOL cache $(cat zpool_cache_zil_partitioned_disklist)
      info "ARC cache completed:\n  1.  $(( $(cat zpool_cache_arc_partitioned_disklist | wc -l) / 2 ))x disk Raid0 (stripe).\n  2.  $(( $(cat zpool_cache_arc_partitioned_disklist | wc -l) / 2 ))x disk Raid1 (mirror)."
      echo
    else
      cat zpool_cache_partitioned_disklist_var02 | grep -w "$ARC_VAR_02 GiB" | sed '$ d' | awk '{ print $2 }' | sed 's/^/\/dev\/disk\/by-id\//' | awk '{print}' ORS=' ' | sed '$s/.$//' | sed '-es/ / mirror /'{1000..1..2} | sed 's/^/mirror /' > zpool_cache_arc_partitioned_disklist
      zpool add $POOL cache $(cat zpool_cache_arc_partitioned_disklist)
      info "ARC cache completed:\n  1.  $(( $(cat zpool_cache_arc_partitioned_disklist | wc -l) / 2 ))x disk Raid0 (stripe).\n  1.  $(( $(cat zpool_cache_arc_partitioned_disklist | wc -l) / 2 ))x disk Raid1 (mirror)."
      echo
    fi
  fi
fi


#### Creating the Storage Pool ####
section "Creating $CT_HOSTNAME storage pool."


# Create Proxmox ZFS Storage pool
msg "Creating ZFS $CT_HOSTNAME storage pool..." 
if [ -d "/$POOL/$CT_HOSTNAME" ]; then
	info "ZFS pool /$POOL/$CT_HOSTNAME exists, not creating this ZFS storage pool..."
else
	zfs create -o compression=on $POOL/$CT_HOSTNAME >/dev/null
  info "ZFS pool created: /$POOL/$CT_HOSTNAME"
  info "ZFS compression set on: /$POOL/$CT_HOSTNAME"
fi
if [ -d "/$POOL/$CT_HOSTNAME" ]; then
  zfs set acltype=posixacl aclinherit=passthrough xattr=sa $POOL/$CT_HOSTNAME >/dev/null
  zfs set xattr=sa $POOL >/dev/null
  info "Posix ACL set on: /$POOL/$CT_HOSTNAME"
fi
echo


#### USB Pass Through ####
section "Setting up USB Passthrough for host $HOSTNAME and File Server $CT_HOSTNAME."

# Add USB Passthrough to CT
echo
box_out '#### USB PASSTHROUGH ####' '' 'There can be good reasons to access USB diskware directly from your File Server CT.' 'To make a physically connected USB device accessible inside a CT the CT configuration' 'file requires modification.' 'In the next step the installation script will display all available USB devices on the host.' 'You need to identify which USB host device ID to passthrough to the CT.' 'The simplest way is to now plugin a physical USB memory stick,' 'for example a SanDisk Cruzer Blade, into a preferred USB port on the host machine.' 'Then to physically identify the USB host device ID' 'to passthrough it will show in the scripts next step. For example:' '' '    5) Bus 002 Device 004: ID 0781:5567 SanDisk Corp. Cruzer Blade' '' 'In this example select No.5 to passthrough.' '' 'In the next step choose the hosts USB device ID to passthrough to the Fileserver CT.'
sleep 1
echo
read -p "Do you want to configure USB pass through for $CT_HOSTNAME [y/n]? " -n 1 -r
echo    # (optional) move to a new line
if [[ $REPLY =~ ^[Yy]$ ]]
then
	USBPASS=0 >/dev/null
else
	USBPASS=1 >/dev/null
	info "Skipping configuration of USB pass through..."
	echo
fi
if [ "$USBPASS" = "0" ]; then
	PS3="Enter your hosts USB device ID to configure (entering numeric) : "
	mapfile -t USB_LIST < <(lsusb | awk '{$3=$4=$5=$6=""; print $0}' | awk '$1=$1')
	select USB_BUS in "${USB_LIST[@]}"
		do test -n "$USB_BUS"
	USB_BUS_ID=$(echo $USB_BUS | awk '{ print $2 }')
	echo
	info "You have chosen ( $USB_BUS ), USB Bus $USB_BUS_ID, to configure for pass through..."
	break
	done
	echo
fi
if [ "$USBPASS" = "0" ]; then
	LXC_CONFIG=/etc/pve/lxc/${CTID}.conf
	cat <<-EOF >> $LXC_CONFIG
	lxc.cgroup.devices.allow: c 189:* rwm
	lxc.mount.entry: /dev/bus/usb/$USB_BUS_ID dev/bus/usb/$USB_BUS_ID none bind,optional,create=dir
	EOF
fi


#### Configuring Filer Server Container ####
section "Configuring your File Server $CT_HOSTNAME."

# Add LXC mount points
#lxc.mount.entry: /tank/data srv/data none bind,create=dir,optional 0 0
msg "Creating LXC mount points..." 
pct set $CTID -mp0 /$POOL/$CT_HOSTNAME,mp=/srv/$CT_HOSTNAME,acl=1 >/dev/null
info "LXC $CTID mount point created: /srv/$CT_HOSTNAME"
echo

# Start container
msg "Starting container..."
pct start $CTID

# Set Container locale
msg "Setting container locale..."
pct exec $CTID -- sed -i "/$LANG/ s/\(^# \)//" /etc/locale.gen
pct exec $CTID -- locale-gen >/dev/null

# Ubuntu fix to avoid prompt to restart services during "apt apgrade"
msg "Patching prompt for user inputs during container upgrades..."
pct exec $CTID -- sudo apt-get -y install debconf-utils >/dev/null
pct exec $CTID -- sudo debconf-get-selections | grep libssl1.0.0:amd64 >/dev/null
pct exec $CTID -- bash -c "echo '* libraries/restart-without-asking boolean true' | sudo debconf-set-selections"

# Set container timezone to match host
msg "Setting container time to match host..."
MOUNT=$(pct mount $CTID | cut -d"'" -f 2)
ln -fs $(readlink /etc/localtime) ${MOUNT}/etc/localtime
pct unmount $CTID && unset MOUNT

# Update container OS
msg "Updating container OS (be patient, might take a while)..."
pct exec $CTID -- apt-get update >/dev/null
pct exec $CTID -- apt-get -qqy upgrade >/dev/null

# Setup container for Fileserver Apps
msg "Starting fileserver installation script..."
echo "#!/usr/bin/env bash" > fileserver_setup_ct_variables.sh
echo "POOL=$POOL" >> fileserver_setup_ct_variables.sh
echo "CT_HOSTNAME=$CT_HOSTNAME" >> fileserver_setup_ct_variables.sh
pct push $CTID fileserver_setup_ct_variables.sh /tmp/fileserver_setup_ct_variables.sh
pct push $CTID fileserver_setup_ct_18.04.sh fileserver_setup_ct_18.04.sh -perms 755
pct exec $CTID -- bash -c "/fileserver_setup_ct_18.04.sh"


# # Get network details and show completion message
IP=$(pct exec $CTID ip a s dev eth0 | sed -n '/inet / s/\// /p' | awk '{print $2}')
echo
echo
msg "Success. File Server installation has completed.\n\nTo manage your File Server use Webmin. You can login to Webmin as root with\nyour root password, or as any user who can use sudo to run commands as root.\n\n  --  ${WHITE}https://${IP}:10000/${NC}\n  --  ${WHITE}https://${CT_HOSTNAME}:10000/${NC}\n"
