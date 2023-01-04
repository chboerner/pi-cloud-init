#!/bin/bash -e

mountpoints=""
## Mapping of fs-types
declare -A fstypes
fstypes=(["Linux"]="" ["W95 FAT32 (LBA)"]="vfat")


# Defaults
scripts_basedir=$(dirname $(readlink -m $0))
working_basedir="$(pwd)"

usage() {
  cat <<EOF
Usage $0 <options>

Image options:
-I <disk image>           Raw OS Image with RasperryPiOS that should be modified.
-T <target image>         This option creates a copy of Raw OS image to work on it. Default is to work on the original.

-C <instance config>      The directory holding the instance specific custom files. Names without leading "/" are
                          expected to be under $scripts_basedir.
                          Within this directory the names bootfs and rootfs are to be used as top levels for the file
                          systems. Everything below will be copied 1:1 to the target file system.
EOF
  exit ${1:-0}
}

## End if no options where given.
[ $# -eq 0 ] && usage 1

while getopts I:T:C:h opt; do
  case $opt in
  I)
    v_sourceimage=$OPTARG
    ;;
  T)
    v_targetimage=$OPTARG
    ;;
  C)
    v_instanceconfigdir=$OPTARG
    if [[ ! $v_instanceconfigdir =~ ^/ ]]; then
      v_instanceconfigdir="${scripts_basedir}/${v_instanceconfigdir}"
    fi
    ;;
  h)
    usage
    ;;
  *)
    usage 1
    ;;
  esac
done


function cleanup() {
  set +e
  for mountpoint in $mountpoints; do
    echo "Unmounting and removing mount point $mountpoint"
    unmout_filesystem $mountpoint
    rm -r $mountpoint
  done
}
trap cleanup EXIT

function mount_filesystem() {
  local image=$1
  local device=$2
  local target=$3

  if [ ! -f $image ]; then
    echo "Source image for mount ($target) could not be found"
    return 1
  fi
  if [ ! -d $target ]; then
    echo "Target directory for mount ($target) could not be found. Creating it..."
    mkdir -p $target
  fi
  startblock=$(fdisk -l -o device,start $v_targetimage | grep ^$device | cut -d ' ' -f 2- | sed -e 's/^\ *//')
  fssize=$(fdisk -l -o device,sectors $v_targetimage | grep ^$device | cut -d ' ' -f 2- | sed -e 's/^\ *//')
  fstype=$(fdisk -l -o device,type $v_targetimage | grep ^$device | cut -d ' ' -f 2- | sed -e 's/^\ *//')

  fstype=${fstypes["$fstype"]}
  offset=$((startblock * 512))
  sizelimit=$((fssize * 512))
  sudo mount -o offset=$offset,sizelimit=$sizelimit ${fstype:+-t $fstype} "$image" "$target"
  if [ $? -ne 0 ]; then
    echo "Error while mounting $image to $target"
    echo "Failed command: sudo mount -o offset=$offset,sizelimit=$sizelimit ${fstype:+-t $fstype} \"$image\" \"$target\""
    return 1
  else
    echo "Mounted $image with offset=$offset and sizelimit=$sizelimit to $target"
  fi
  mountpoints="$mountpoints $target"
}

function unmout_filesystem() {
  local mountpoint=$1
  sync -f "${mountpoint}"
  if [ $(fuser -Mm "${mountpoint}" 2>/dev/null | wc -w) -gt 0 ]; then
    echo "Warning: There are active processes on the filesystem mounted at $mountpoint:"
    fuser -Mm $mountpoint
    fuser -Mk $mountpoint
  fi

  umount -f $mountpoint
}

function get_filesystems() {
  local image=$1
  LANG=C fdisk -l -o device "$image" | sed -n '/^Device$/,$p' | tail -n +2
}


function check_if_sudo() {
  if [ $(id -u) -ne 0 ]; then
    echo "You need to run this script with sudo. Otherwise it's not possible to modify content in the image that belongs to the root user."
    exit 1
  fi
  if [ -z "$SUDO_UID" ]; then
    echo "Warning: you're running this script as logged in root. This is not recommended."
  fi
}

function prepare_bootfs() {
  local fs_base=$1
  echo "Preparing boot filesystem"

  if [ -d ${v_instanceconfigdir}/bootfs ]; then
    cp -vr ${v_instanceconfigdir}/bootfs/* $fs_base/
  fi
}

function prepare_rootfs() {
  local fs_base=$1
  echo "Preparing root filesystem"

  if [ -d ${v_instanceconfigdir}/rootfs ]; then
    cp -vr ${v_instanceconfigdir}/rootfs/* $fs_base/
  fi
}

function main() {
  ## Base checks
  [ -z "$v_sourceimage" ] && {
    echo "Please specify image which shall be modified."
    exit 1
  }
  [ ! -e "$v_sourceimage" ] && { echo "Source image $v_sourceimage could not be found." && exit 1; }

  if [ -z "$v_targetimage" ]; then
    echo "Target image is empty, all work is done on $v_sourceimage instead."
    v_targetimage=$v_sourceimage
  else
    echo "Creating a copy of $v_sourceimage to $v_targetimage. Work will be done there."
    cp -v $v_sourceimage $v_targetimage
  fi

  boot_fs=""
  root_fs=""

  echo "Finding filesystems in OS image"
  devices=$(get_filesystems $v_targetimage)
  echo "Found filesystems:"
  echo "$devices"
  for device in $devices; do
    echo "Mounting filesystem $device"
    mountpoint=$(mktemp -d -p $working_basedir)
    mount_filesystem "$v_targetimage" "$device" "$mountpoint"

    # Checking where to find which filesystem - optimistically looking for cmdline.txt in BootFS and rpi-update in RootFS
    echo "Checking if we have a root or boot fs here..."
    if [ -e "$mountpoint/cmdline.txt" ]; then
      echo "Found boot filesystem"
      boot_fs=$mountpoint
    elif [ -e "$mountpoint/usr/bin/rpi-update" ]; then
      echo "Found root filesystem"
      root_fs=$mountpoint
    fi
  done

  [ -n "$boot_fs" ] && prepare_bootfs $boot_fs
  [ -n "$root_fs" ] && prepare_rootfs $root_fs

}

check_if_sudo
main

echo "Now run \"sudo ${scripts_basedir}/burnRaspiImage.sh -I $v_targetimage -D [StorageDevice]\" to transfer the image."