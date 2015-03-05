#!/bin/bash

# This script is used to debootstrap Ubuntu onto a disk image or an SD card.
# (c) Mattias Schlenker - licensed under LGPL v2.1
# 
# It relies heavily on environment variables. Set them before running this
# script either by exporting them or by prepending them to the command. 
# 
# Currently only supports Banana Pi M1! More to follow...
# Currently only allows for installation of Ubuntu! Debian Jessie will follow...
#
# Reference of environment variables:
#
# PIDISTRO=vivid # Ubuntu release to debootstrap, use vivid, utopic or precise
# PIPACKAGES="lubuntu-desktop language-support-de" # Additional packages to include
# PITARGET=/dev/sdc # Path to a block device or name of a file - currently inactive
# PISIZE=4000000000 # Size of the image to create, will be rounded down to full MB
# PISWAP=500000000  # Size of swap partition - currently inactive
# PIHOSTNAME=pibuntu # Hostname to use
# PIUSER=mattias # Create an unprivileged user - leave empty to skip
#
# IGNOREDPKG=1 # Use after installing debootstrap on non Debian OS

DEBOOTSTRAP=1.0.67
if [ -z "$PISIZE" ] ; then
	PISIZE=4000000000
fi

me=` id -u `
if [ "$me" -gt 0 ] ; then
	echo 'Please run this script with root privileges!'
	exit 1
fi

# Check the architecture we are running on

case ` uname -m ` in
	armv7l )
		echo "OK, running on ARMv7..."
		echo "Called as $0"
	;;
	* )
		echo ':-( Cross compiling the kernel and bootloader is not yet supported'
		echo 'Please run this script on a proper ARMv7 board (Raspberry Pi 2, Banana Pi)'
		exit 1
	;;
esac

# Check for some programs that are needed

if which dpkg ; then
	echo "OK, found dpkg..."
elif [ "$IGNOREDPKG" -gt 0 ] ; then
	echo "OK, ignoring dpkg..."
else
	echo ':-( Dpkg was not found, this script is not yet tested on non-debian distributions'
	exit 1
fi

# Check for more programs

progsneeded="gcc bc patch make mkimage git wget kpartx parted mkfs.msdos mkfs.ext4"
for p in $progsneeded ; do
	which $p
	retval=$?
	if [ "$retval" -gt 0 ] ; then
		echo "$p is missing. Please install dependencies:"
		echo "apt-get -y install bc libncurses5-dev build-essential u-boot-tools git wget kpartx parted dosfstools e2fsprogs"
		exit 1
	else
		echo "OK, found $p..."
	fi
done

# Download and unpack debootstrap:

test -f debootstrap_${DEBOOTSTRAP}.tar.gz || \
wget http://ports.ubuntu.com/pool/main/d/debootstrap/debootstrap_${DEBOOTSTRAP}.tar.gz

test -f debootstrap_${DEBOOTSTRAP}.tar.gz && \
tar xzf debootstrap_${DEBOOTSTRAP}.tar.gz && \
mkdir -p /usr/share/debootstrap && \
mount --bind debootstrap-${DEBOOTSTRAP} /usr/share/debootstrap

if debootstrap-${DEBOOTSTRAP}/debootstrap --help ; then
	echo "OK, debootstrap works"
else
	umount /usr/share/debootstrap
	exit 1
fi

# Calculate the size of the image

PIBLOCKS=$(( $PISIZE / 1048576 ))
echo "OK, using $PIBLOCKS one MB blocks"
dd if=/dev/zero bs=1048576 count=1 seek=$(( $PIBLOCKS - 1 )) of=disk.img 
modprobe -v loop 
FREELOOP=` losetup -f `
retval=$?
if [ "$retval" -gt 0 ] ; then
	echo ':-( No free loop device found.'
	exit 1
fi

echo "OK, using loop device $FREELOOP"
losetup $FREELOOP disk.img
echo "OK, partitioning the device"
parted -s $FREELOOP mklabel msdos
parted -s $FREELOOP unit B mkpart primary fat16 1048576 67108863
parted -s $FREELOOP unit B mkpart primary ext2 67108864 '100%'
parted -s $FREELOOP unit B print
echo "OK, creating device mappings"
kpartx -s -v -a $FREELOOP
echo "OK, creating filesystems"
mkfs.msdos /dev/mapper/$( basename $FREELOOP )p1
mkfs.ext4  /dev/mapper/$( basename $FREELOOP )p2

# Clean up 
for n in ` seq 1 9 ` ; do
	dmsetup remove /dev/mapper/$( basename $FREELOOP )p${n} > /dev/null 2>&1  
done 
losetup -d $FREELOOP 
umount /usr/share/debootstrap


