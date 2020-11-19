#!/usr/bin/env bash
set -euo pipefail

debootstrap_dir=/mnt
root_filesystem=img.ext2.qcow2

# 1.5Gbytes
dd if=/dev/zero of=1445.img bs=1024 count=1 seek=1536k

parted -s 1445.img -- mklabel msdos mkpart primary 1m 1.5g toggle 1 boot
losetup --show -f 1445.img
# prints out `/dev/loopX`, enter this on the next lin
partprobe /dev/loop0
# only have to make the filesytem once --> if you are troubleshooting steps, do not redo this line
mkfs -t ext2 /dev/loop0p1
mount /dev/loop0p1 /mnt

# install required programs
sudo apt-get install -y \
  debootstrap \
  libguestfs-tools \
  git \
  qemu-system-x86 \
  ;

debootstrap --verbose --components=main,contrib,non-free \
--include=firmware-realtek,linux-image-amd64,grub-pc,ssh,vim \
--exclude=nano \
--arch amd64 jessie "${debootstrap_dir}" http://ftp.us.debian.org/debian

# Remount root filesystem as rw.
# Otherwise, systemd shows:
#     [FAILED] Failed to start Create Volatile Files and Directories.
# and then this leads to further failures in the network setup.
cat << EOF | sudo tee "${debootstrap_dir}/etc/fstab"
    /dev/sda / ext4 errors=remount-ro,acl 0 1
EOF

# Set root password.
echo 'root:root' | sudo chroot "$debootstrap_dir" chpasswd

# Generate image file from debootstrap directory.
# Leave 1Gb extra empty space in the image.
sudo virt-make-fs \
    --format qcow2 \
    --size +1G \
    --type ext2 \
    "$debootstrap_dir" \
    "$root_filesystem" \
    ;

linux_img="${debootstrap_dir}/boot/vmlinuz-"*
    
qemu-system-x86_64 \
  -append 'console=ttyS0 root=/dev/sda' \
  -drive "file=${root_filesystem},format=qcow2" \
  -enable-kvm \
  -serial mon:stdio \
  -m 2G \
  -kernel "$linux_img" \
  -device rtl8139,netdev=net0 \
  -netdev user,id=net0


qemu-system-x86_64 -hda 1445.img -m 1024 -vnc :0
