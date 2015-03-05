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
# PIDISTRO=vivid # Ubuntu release to debootstrap, use vivid, utopic, trusty or precise
# PIPACKAGES="lubuntu-desktop language-support-de" # Additional packages to include
# PITARGET=/dev/sdc # Path to a block device or name of a file - currently inactive
# PISIZE=4000000000 # Size of the image to create, will be rounded down to full MB
# PISWAP=500000000  # Size of swap partition - currently inactive
# PIHOSTNAME=pibuntu # Hostname to use
# PIUSER=mattias # Create an unprivileged user - leave empty to skip
#
# IGNOREDPKG=1 # Use after installing debootstrap on non Debian OS

DEBOOTSTRAP=1.0.67
KERNELMAJOR=3.19

if [ -z "$PISIZE" ] ; then
	PISIZE=4000000000
fi
if [ -z "$PIDISTRO" ] ; then
	PIDISTRO="utopic" 
fi

me=` id -u `
if [ "$me" -gt 0 ] ; then
	echo 'Please run this script with root privileges!'
	exit 1
fi

# Find out the basedir

basedir=` dirname "$0" `
basedir=` dirname "$basedir" `

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

# Download and install debootstrap:

test -f debootstrap_${DEBOOTSTRAP}_all.deb || \
wget http://archive.ubuntu.com/ubuntu/pool/main/d/debootstrap/debootstrap_${DEBOOTSTRAP}_all.deb
# wget http://ports.ubuntu.com/pool/main/d/debootstrap/debootstrap_${DEBOOTSTRAP}.tar.gz
dpkg -i debootstrap_${DEBOOTSTRAP}_all.deb
# test -f debootstrap_${DEBOOTSTRAP}.tar.gz && \
# tar xzf debootstrap_${DEBOOTSTRAP}.tar.gz && \
# mkdir -p /usr/share/debootstrap && \
# mount --bind debootstrap-${DEBOOTSTRAP} /usr/share/debootstrap

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
	umount /usr/share/debootstrap
	exit 1
fi

# Prepare the disk image

echo "OK, using loop device $FREELOOP"
losetup $FREELOOP disk.img
dd if=/dev/zero bs=1048576 count=128 of=$FREELOOP
echo "OK, partitioning the device"
parted -s $FREELOOP mklabel msdos
parted -s $FREELOOP unit B mkpart primary fat16 1048576 67108863
parted -s $FREELOOP unit B mkpart primary ext2 67108864 75497471
parted -s $FREELOOP unit B mkpart primary ext2 75497472 '100%'
parted -s $FREELOOP unit B print
echo "OK, creating device mappings"
kpartx -s -v -a $FREELOOP
if [ -b /dev/mapper/$( basename $FREELOOP )p1 ] ; then
	echo "OK, mapped devices created"
else
	echo ':-( Device mapper is not working.'
	umount /usr/share/debootstrap
	losetup -d $FREELOOP 
	exit 1
fi

echo "OK, creating filesystems"
for n in 1 2 3 ; do
	dd if=/dev/zero bs=1M count=8 of=/dev/mapper/$( basename $FREELOOP )p${n} 
done 
mkfs.msdos /dev/mapper/$( basename $FREELOOP )p1
mkfs.ext4  /dev/mapper/$( basename $FREELOOP )p3

# Mount the disk image and install the base filesystem
mkdir -p targetfs
mount /dev/mapper/$( basename $FREELOOP )p3 targetfs
debootstrap-${DEBOOTSTRAP}/debootstrap --verbose \
	--arch armhf $PIDISTRO targetfs http://ports.ubuntu.com/
retval=$?

if [ "$retval" -gt 0 ] ; then
	echo ':-/ Oops debootstrap failed with exit code '"$retval"
	# umount targetfs
	# for n in ` seq 1 9 ` ; do
	#	dmsetup remove /dev/mapper/$( basename $FREELOOP )p${n} > /dev/null 2>&1  
	# done 
	# losetup -d $FREELOOP 
	# exit 1
fi

# Install additional software

mount --bind /dev targetfs/dev
mount -t devpts none targetfs/dev/pts
mount -t proc none targetfs/proc 
mount --bind /sys targetfs/sys
mount -t tmpfs -o mode=0755,size=256M tmpfs targetfs/tmp
mount -t tmpfs -o mode=0755,size=64M  tmpfs targetfs/root
mkdir -p packages
mount --bind packages targetfs/var/cache/apt/archives
echo 'nameserver 8.8.8.8' > targetfs/etc/resolv.conf 
install -m 0644 "${basedir}/configfiles/sources.list.ubuntu" targetfs/etc/apt/sources.list 
sed -i 's/UBUNTUCODENAME/'${PIDISTRO}'/g' targetfs/etc/apt/sources.list
LC_ALL=POSIX chroot targetfs apt-get update
LC_ALL=POSIX chroot targetfs apt-get -y dist-upgrade

for p in language-pack-en $PIPACKAGES; do
	LC_ALL=POSIX chroot targetfs apt-get -y install $p
done

for d in dev/pts dev proc sys tmp root var/cache/apt/archives ; do
	umount targetfs/${d} 
done

# Configure /etc/fstab and console

# Build and install a kernel for Raspberry Pi 2

# Build and install a kernel for Banana Pi M1

test -f linux-${KERNELMAJOR}.tar.xz || \
wget https://www.kernel.org/pub/linux/kernel/v3.x/linux-${KERNELMAJOR}.tar.xz
test -d linux-${KERNELMAJOR} || tar xJf linux-${KERNELMAJOR}.tar.xz
( cd linux-${KERNELMAJOR} ; make distclean )
install -m 0644 "${basedir}/configfiles/dotconfig.bananapi.m1" linux-${KERNELMAJOR}/.config
cd linux-${KERNELMAJOR}
yes '' | make oldconfig
make -j $( grep -c processor /proc/cpuinfo ) LOADADDR=0x40008000 uImage modules dtbs
INSTALL_MOD_PATH=../targetfs make modules_install
install -m 0644 arch/arm/boot/uImage ../targetfs/boot
cd ..

# Build and install the bootloader for Raspberry Pi 2

# Build and install U-Boot for Banana Pi M1

# Install basic configuration

# Add a user if requested

# Clean up 
umount targetfs/boot
umount targetfs
retval=$?
if [ "$retval" -gt 0 ] ; then
	echo ':-/ Oops umount failed. This should not be a big deal - just reboot now!'
	exit 0
fi

for n in ` seq 1 9 ` ; do
	dmsetup remove /dev/mapper/$( basename $FREELOOP )p${n} > /dev/null 2>&1  
done 
losetup -d $FREELOOP 
umount /usr/share/debootstrap


