#!/bin/bash
# lun0 (swap, opt, tmp & home volumes) bootstrap script for Azure Linux SLES instances
# Author: chouds27
exec > /root/bootstrap-lun0.log 2>&1
set -ex

##############CHECK IF WE ARE RUNNING AS ROOT USER##############
[[ ${UID} -ne 0 ]] && { echo "[ERROR] $0 must be run as root. Exiting." >&2; exit 100; }

### Params ###
params_username=${1:-azureuser}

### XFS partitions ###
pvcreate /dev/disk/azure/scsi1/lun0
vgcreate vg0 /dev/disk/azure/scsi1/lun0

lvcreate -L 8G -n swap vg0
lvcreate -L 10G -n opt vg0
lvcreate -L 2G -n tmp vg0
lvcreate -L 10G -n home vg0

mkswap /dev/mapper/vg0-swap
mkfs.xfs /dev/mapper/vg0-opt
mkfs.xfs /dev/mapper/vg0-tmp
mkfs.xfs /dev/mapper/vg0-home
swapon /dev/mapper/vg0-swap
mount /dev/mapper/vg0-tmp /tmp
mkdir /tmp/home/
mv -f /home/$params_username /tmp/
mount /dev/mapper/vg0-home /home
mv -f /tmp/$params_username /home

echo ''
echo '/dev/mapper/vg0-swap swap swap defaults 0 2' >> /etc/fstab
echo '/dev/mapper/vg0-opt /opt xfs nodev 0 2' >> /etc/fstab
echo '/dev/mapper/vg0-tmp /tmp xfs defaults,nodev,nosuid,noexec 0 2' >> /etc/fstab
echo '/tmp /var/tmp none rw,noexec,nosuid,nodev,bind 0 2' >> /etc/fstab
echo '/dev/mapper/vg0-home /home xfs nodev 0 2' >> /etc/fstab

### Mounts ###
/usr/bin/mount -a; chmod a+rwxt /tmp

exit 0