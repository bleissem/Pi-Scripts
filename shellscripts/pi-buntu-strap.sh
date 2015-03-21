#!/bin/bash

# This script is used to debootstrap Ubuntu onto a disk image or an SD card.
# (c) Mattias Schlenker - licensed under LGPL v2.1
# 
# It relies heavily on environment variables. Set them before running this
# script either by exporting them or by prepending them to the command. 
# 
# Currently only supports Banana Pi M1 and Raspberry Pi 2! More to follow...
# Currently only allows for installation of Ubuntu! Debian Jessie will follow...
#
# Reference of environment variables:
#
# PIDISTRO=vivid # Ubuntu release to debootstrap, use vivid, utopic, trusty or precise
# PIPACKAGES="lubuntu-desktop language-support-de" # Additional packages to include
# PITARGET=/dev/sdc # Path to a block device or name of a file - currently inactive
# PISIZE=4000000000 # Size of the image to create, will be rounded down to full MB
# PISWAP=500000000  # Size of swap partition
# PIHOSTNAME=pibuntu # Hostname to use
# PIXKBMODEL="pc105"
# PIXKBLAYOUT="de"
# PIXKBVARIANT=""
# PIXKBOPTIONS=""
# PILANG=en_US.UTF-8 # Set the default locale
# PIUSER=mattias # Create an unprivileged user - leave empty to skip
#
# IGNOREDPKG=1 # Use after installing debootstrap on non Debian OS

DEBOOTSTRAP=1.0.67
KERNELMAJOR=3.19
KERNELPATCH=3.19.2
KPATCHES="linux-3.19-b53.patch"

if [ -z "$PISIZE" ] ; then
	PISIZE=4000000000
fi
if [ -z "$PIDISTRO" ] ; then
	PIDISTRO="utopic" 
fi
if [ -z "$PILANG" ] ; then
	PILANG="en_US.UTF-8" 
fi
if [ -z "$PISWAP" ] ; then
	PISWAP="4194304" 
fi
if [ -z "$PIHOSTNAME" ] ; then
	PIHOSTNAME="pibuntu" 
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

progsneeded="gcc bc patch make mkimage git wget kpartx parted mkfs.msdos mkfs.ext4 lsof"
for p in $progsneeded ; do
	which $p
	retval=$?
	if [ "$retval" -gt 0 ] ; then
		echo "$p is missing. Please install dependencies:"
		echo "apt-get -y install bc libncurses5-dev build-essential u-boot-tools git wget kpartx parted dosfstools e2fsprogs lsof"
		exit 1
	else
		echo "OK, found $p..."
	fi
done

# Download and install debootstrap:

test -f debootstrap_${DEBOOTSTRAP}_all.deb || \
wget http://archive.ubuntu.com/ubuntu/pool/main/d/debootstrap/debootstrap_${DEBOOTSTRAP}_all.deb
dpkg -i debootstrap_${DEBOOTSTRAP}_all.deb

# Calculate the size of the image

PIBLOCKS=$(( $PISIZE / 1048576 ))
SWAPBLOCKS=$(( $PISWAP / 1048576 ))
SWAPBYTES=$(( $SWAPBLOCKS * 1048576 ))
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
parted -s $FREELOOP unit B mkpart primary ext2 67108864 $(( 67108864 + $SWAPBYTES - 1 ))
parted -s $FREELOOP unit B mkpart primary ext2 $(( 67108864 + $SWAPBYTES )) '100%'
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
mkswap     /dev/mapper/$( basename $FREELOOP )p2
mkfs.ext4  /dev/mapper/$( basename $FREELOOP )p3

# Download and unpack necessary stuff:
#

# u-boot for Banana Pi

test -d u-boot || git clone http://git.denx.de/u-boot.git
( cd u-boot ; git pull )

# Bootloader/Firmware for Raspberry Pi 2

mkdir -p rpi2
( cd rpi2 
test -d firmware || git clone https://github.com/raspberrypi/firmware
cd firmware 
git pull )

# Kernel for Banana Pi

test -f linux-${KERNELMAJOR}.tar.xz || \
wget https://www.kernel.org/pub/linux/kernel/v3.x/linux-${KERNELMAJOR}.tar.xz

if [ -z "$KERNELPATCH" ] ; then
	test -d linux-${KERNELMAJOR} || tar xJf linux-${KERNELMAJOR}.tar.xz
elif [ -f patch-${KERNELPATCH}.xz ] ; then
	echo "OK, assuming patching done..."
else
	wget https://www.kernel.org/pub/linux/kernel/v3.x/patch-${KERNELPATCH}.xz
	rm -rf linux-${KERNELMAJOR} 
	tar xJf linux-${KERNELMAJOR}.tar.xz
	( cd linux-${KERNELMAJOR} ; unxz -c ../patch-${KERNELPATCH}.xz | patch -p1 )
	for f in $KPATCHES ; do
		( cd linux-${KERNELMAJOR} ; cat ${basedir}/patches/${f} | patch -p1 )
	done
fi

# Kernel for Raspberry Pi

( cd rpi2 
test -d linux || git clone https://github.com/raspberrypi/linux
cd linux 
git pull
git checkout rpi-3.18.y )

# Mount the disk image and install the base filesystem
mkdir -p targetfs
mount /dev/mapper/$( basename $FREELOOP )p3 targetfs
debootstrap --verbose --arch armhf $PIDISTRO targetfs http://ports.ubuntu.com/
retval=$?

if [ "$retval" -gt 0 ] ; then
	echo ':-/ Oops debootstrap failed with exit code '"$retval"
	echo 'Press enter to continue anyway.'
	read x
fi

# Configure /etc/fstab

install -m 0755 "${basedir}/configfiles/etc.fstab" targetfs/etc/fstab
[ "$SWAPBLOCKS" -gt 63 ] && sed -i 's%#/dev/mmcblk0p2%/dev/mmcblk0p2%g' targetfs/etc/fstab

# Build and install U-Boot for Banana Pi M1

make -C u-boot clean
make -C u-boot Bananapi_config 
make -C u-boot -j $( grep -c processor /proc/cpuinfo ) 
mkimage -C none -A arm -T script -d "${basedir}/configfiles/boot.cmd.bananapi.m1" boot.scr
dd if=u-boot/spl/sunxi-spl.bin of=$FREELOOP bs=1024 seek=8
dd if=u-boot/u-boot.img        of=$FREELOOP bs=1024 seek=40
mount /dev/mapper/$( basename $FREELOOP )p1 targetfs/boot

# Build and install the bootloader for Raspberry Pi 2

for f in bcm2709-rpi-2-b.dtb bootcode.bin \
	fixup.dat fixup_cd.dat fixup_x.dat \
	start.elf start_cd.elf start_x.elf ; do
	install -m 0644 rpi2/firmware/boot/${f} targetfs/boot/
done
for f in cmdline.txt config.txt ; do
	install -m 0644 "${basedir}/configfiles/${f}.raspberrypi.2" targetfs/boot/${f}
done
sed -i 's/mmcblk0p2/mmcblk0p3/g' targetfs/boot/cmdline.txt

# Build and install a kernel for Raspberry Pi 2

install -m 0644 "${basedir}/configfiles/dotconfig.raspberrypi.2" rpi2/linux/.config
yes '' | make -C rpi2/linux oldconfig
make -C rpi2/linux -j $( grep -c processor /proc/cpuinfo ) 
make -C rpi2/linux -j $( grep -c processor /proc/cpuinfo ) modules
INSTALL_MOD_PATH=../../targetfs make -C rpi2/linux modules_install 
install -m 0644 rpi2/linux/arch/arm/boot/Image targetfs/boot/kernel7.img

# Build and install a kernel for Banana Pi M1

install -m 0644 "${basedir}/configfiles/dotconfig.bananapi.m1.testing" linux-${KERNELMAJOR}/.config
yes '' | make -C linux-${KERNELMAJOR} oldconfig
make -C linux-${KERNELMAJOR} -j $( grep -c processor /proc/cpuinfo ) LOADADDR=0x40008000 uImage modules dtbs
( cd linux-${KERNELMAJOR} ; INSTALL_MOD_PATH=../targetfs make modules_install )
install -m 0644 boot.scr targetfs/boot
install -m 0644 "${basedir}/configfiles/boot.cmd.bananapi.m1" targetfs/boot/boot.cmd
install -m 0644 linux-${KERNELMAJOR}/arch/arm/boot/uImage targetfs/boot
install -m 0644 linux-${KERNELMAJOR}/arch/arm/boot/dts/sun7i-a20-bananapi.dtb targetfs/boot

# Install basic configuration

install -m 0755 "${basedir}/configfiles/etc.default.keyboard" targetfs/etc/default/keyboard
[ -n "$PIXKBMODEL" ] && echo 'XKBMODEL="'"$PIXKBMODEL"'"' >>  targetfs/etc/default/keyboard
[ -n "$PIXKBVARIANT" ] && echo 'XKBVARIANT="'"$PIXKBVARIANT"'"' >>  targetfs/etc/default/keyboard
[ -n "$PIXKBLAYOUT" ] && echo 'XKBLAYOUT="'"$PIXKBLAYOUT"'"' >>  targetfs/etc/default/keyboard
[ -n "$PIXKBOPTIONS" ] && echo 'XKBOPTIONS="'"$PIXKBOPTIONS"'"' >>  targetfs/etc/default/keyboard
echo 'LANG="'"$PILANG"'"' > targetfs/etc/default/locale
echo 'LC_MESSAGES=POSIX' >> targetfs/etc/default/locale
chmod 0755 targetfs/etc/default/locale
install -m 0644 "${basedir}/configfiles/etc.network.interfaces.m1" targetfs/etc/network/interfaces
echo "$PIHOSTNAME" > targetfs/etc/hostname
# FIXME: This seems to fit upstart only
if [ -f "targetfs/etc/init/tty1.conf" ] ; then
	cp -v targetfs/etc/init/{tty1,ttyS0}.conf
	sed -i 's/tty1/ttyS0/g' targetfs/etc/init/ttyS0.conf
fi

# Install Pi-Scripts - FIME, move this to a debian package
install -m 0755 "${basedir}/shellscripts/pi-firstrun" targetfs/usr/sbin
install -m 0755 "${basedir}/shellscripts/pi-stretch" targetfs/usr/sbin
install -m 0755 "${basedir}/shellscripts/pi-update" targetfs/usr/sbin
echo '' >> "targetfs/etc/rc.local"
sed -i 's%exit 0%# exit 0%g' "targetfs/etc/rc.local"
echo '/usr/sbin/pi-firstrun' >> "targetfs/etc/rc.local"
echo 'exit 0' >> "targetfs/etc/rc.local"
for f in .stretchfs .stretchpart .firstrun ; do
	touch "targetfs/${f}"
done

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

for p in language-pack-en vlan parted $PIPACKAGES; do
	LC_ALL=POSIX chroot targetfs apt-get -y install $p
done

LC_ALL=POSIX chroot targetfs shadowconfig on
echo 'Setting root password for your image:'
LC_ALL=POSIX chroot targetfs passwd

# Add a user if requested
if [ -n "$PIUSER" ] ; then
	LC_ALL=POSIX chroot targetfs adduser "$PIUSER"
	for group in adm dialout lpadmin sudo ; do
		LC_ALL=POSIX chroot targetfs usermod -aG $group "$PIUSER"
	done
fi

# Clean up 
kill -9 ` lsof | grep targetfs | awk '{print $2}' | uniq `
for d in dev/pts dev proc sys tmp root var/cache/apt/archives ; do
	umount targetfs/${d} 
done
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
