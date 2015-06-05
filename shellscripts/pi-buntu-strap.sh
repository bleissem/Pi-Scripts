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
# PIXTRADEBS="/path/to/package.deb" # space separated list of extra debs to install
#
# IGNOREDPKG=1 # Use after installing debootstrap on non Debian OS

DEBOOTSTRAP=1.0.67
# KERNELMAJOR=3.19
# KERNELPATCH=.5 # 3.19.5
KERNELMAJOR=4.0
KERNELPATCH=.4
# KPATCHES="linux-3.19-b53.patch"
KPATCHES="linux-4.0-b53.patch"
#BPIKERNELCONF="dotconfig.bananapi.m1.testing"
BPIKERNELCONF="dotconfig-4.0"
XTRAMODULES="b53_spi b53_mdio b53_srab ipvlan 8192"
BLACKLIST="rtl8192cu"
MINPACKAGES="language-pack-en vlan parted bridge-utils psmisc screen iw"

if [ -z "$PISIZE" ] ; then
	PISIZE=4000000000
fi
if [ -z "$PIDISTRO" ] ; then
	PIDISTRO="vivid" 
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
if echo "$0" | grep -q -v '^/' ; then
	echo 'Please run this with absolute pathnames!'
	exit 1
fi

# Find out the basedir

basedir=` dirname "$0" `
basedir=` dirname "$basedir" `

####### Define some functions

# Check the architecture we are running on
function check_arch {
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
}

# Check for some programs that are needed
function check_dpkg {
	if which dpkg ; then
		echo "OK, found dpkg..."
	elif [ "$IGNOREDPKG" -gt 0 ] ; then
		echo "OK, ignoring dpkg..."
	else
		echo ':-( Dpkg was not found, this script is not yet tested on non-debian distributions'
		exit 1
	fi
}

# Check for more programs
function check_progs {
	progsneeded="gcc bc patch make mkimage git wget kpartx parted mkfs.msdos mkfs.ext4 lsof ruby dtc"
	for p in $progsneeded ; do
		which $p
		retval=$?
		if [ "$retval" -gt 0 ] ; then
			echo "$p is missing. Please install dependencies:"
			echo "apt-get -y install bc libncurses5-dev build-essential device-tree-compiler u-boot-tools git wget kpartx parted dosfstools e2fsprogs lsof ruby2.0"
			exit 1
		else
			echo "OK, found $p..."
		fi
	done
}

# Download and unpack Vanilla kernel

function pull_vanilla_kernel {
	test -f linux-${KERNELMAJOR}.tar.xz || \
	wget https://www.kernel.org/pub/linux/kernel/v4.x/linux-${KERNELMAJOR}.tar.xz
	if [ -n "$KERNELPATCH" ] ; then
		test -f patch-${KERNELMAJOR}${KERNELPATCH}.xz || \
			wget https://www.kernel.org/pub/linux/kernel/v4.x/patch-${KERNELMAJOR}${KERNELPATCH}.xz
	fi
	if [ -f linux-${KERNELMAJOR}${KERNELPATCH}.ready ] ; then
		echo "OK, kernel already prepared"
	elif [ -z "$KERNELPATCH" ] ; then
		tar xJf linux-${KERNELMAJOR}.tar.xz
		for f in $KPATCHES ; do
			( cd linux-${KERNELMAJOR} ; cat ${basedir}/patches/${f} | patch -p1 )
		done
		touch linux-${KERNELMAJOR}.ready
	else
		rm -rf linux-${KERNELMAJOR}
		tar xJf linux-${KERNELMAJOR}.tar.xz
		( cd linux-${KERNELMAJOR} ; unxz -c ../patch-${KERNELMAJOR}${KERNELPATCH}.xz | patch -p1 )
		for f in $KPATCHES ; do
			( cd linux-${KERNELMAJOR} ; cat ${basedir}/patches/${f} | patch -p1 )
		done
		mv linux-${KERNELMAJOR} linux-${KERNELMAJOR}${KERNELPATCH}
		touch linux-${KERNELMAJOR}${KERNELPATCH}.ready
	fi
}

check_arch
check_dpkg
check_progs
pull_vanilla_kernel

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

# RTL8192 for Banana Pi
if [ -d rt8192cu ] ; then
	( cd rt8192cu ; git pull )
else
	git clone https://github.com/dz0ny/rt8192cu.git
fi

# Kernel for Raspberry Pi
( cd rpi2 
test -d linux || git clone https://github.com/raspberrypi/linux
cd linux 
git pull
git checkout rpi-3.18.y )

# Linux Firmware
if [ -d linux-firmware ] ; then
	( cd linux-firmware ; git pull )
else
	git clone git://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git
fi

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

echo '===> Building u-boot for Banana Pi - logging to u-boot.log'
make -C u-boot clean > u-boot.log
make -C u-boot Bananapi_config >> u-boot.log 
make -C u-boot -j $( grep -c processor /proc/cpuinfo ) >> u-boot.log  
mkimage -C none -A arm -T script -d "${basedir}/configfiles/boot.cmd.bananapi.m1" boot.scr >> u-boot.log  
echo '===> Installing u-boot for Banana Pi'
dd if=u-boot/spl/sunxi-spl.bin of=$FREELOOP bs=1024 seek=8
dd if=u-boot/u-boot.img        of=$FREELOOP bs=1024 seek=40
mount /dev/mapper/$( basename $FREELOOP )p1 targetfs/boot
echo '   > done.'

# Build and install the bootloader for Raspberry Pi 2
echo '===> Installing bootloader for Raspberry Pi'
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
echo '===> Building kernel for Raspberry Pi - logging to kernel.rpi.build.log'
install -m 0644 "${basedir}/configfiles/dotconfig.raspberrypi.2" rpi2/linux/.config
yes '' | make -C rpi2/linux oldconfig > kernel.rpi.build.log
make -C rpi2/linux -j $( grep -c processor /proc/cpuinfo )  >> kernel.rpi.build.log
make -C rpi2/linux -j $( grep -c processor /proc/cpuinfo ) modules >> kernel.rpi.build.log
echo '===> Installing kernel for Raspberry Pi - logging to kernel.rpi.install.log'
INSTALL_MOD_PATH=../../targetfs make -C rpi2/linux modules_install  > kernel.rpi.install.log
install -m 0644 rpi2/linux/arch/arm/boot/Image targetfs/boot/kernel7.img >> kernel.rpi.install.log

# Build and install a kernel for Banana Pi M1
echo '===> Building kernel for Banana Pi - logging to kernel.bpi.build.log'
install -m 0644 "${basedir}/configfiles/${BPIKERNELCONF}" linux-${KERNELMAJOR}${KERNELPATCH}/.config
yes '' | make -C linux-${KERNELMAJOR}${KERNELPATCH} oldconfig
make -C linux-${KERNELMAJOR}${KERNELPATCH} -j $( grep -c processor /proc/cpuinfo ) LOADADDR=0x40008000 uImage modules dtbs > kernel.bpi.build.log
( cd linux-${KERNELMAJOR}${KERNELPATCH} ; INSTALL_MOD_PATH=../targetfs make modules_install ) >> kernel.bpi.build.log
echo '===> Installing kernel for Banana Pi - logging to kernel.bpi.install.log'
install -m 0644 boot.scr targetfs/boot
install -m 0644 "${basedir}/configfiles/boot.cmd.bananapi.m1" targetfs/boot/boot.cmd > kernel.bpi.install.log
install -m 0644 linux-${KERNELMAJOR}${KERNELPATCH}/arch/arm/boot/uImage targetfs/boot >> kernel.bpi.install.log
install -m 0644 linux-${KERNELMAJOR}${KERNELPATCH}/arch/arm/boot/dts/sun7i-a20-bananapi.dtb targetfs/boot >> kernel.bpi.install.log

# Build and install the rt8192cu module for Banana Pi R1

CURRENTPWD=` pwd `
KLOCALVERS=` cat linux-${KERNELMAJOR}${KERNELPATCH}/.config | grep CONFIG_LOCALVERSION= | awk -F '=' '{print $2}' | sed 's/"//g' ` 
make -j 2 -C ${CURRENTPWD}/linux-${KERNELMAJOR}${KERNELPATCH} M=${CURRENTPWD}/rt8192cu USER_EXTRA_CFLAGS='-Wno-error=date-time'
mkdir -p targetfs/lib/modules/${KERNELMAJOR}${KERNELPATCH}${KLOCALVERS}/extra 
install -m 0644 rt8192cu/8192cu.ko targetfs/lib/modules/${KERNELMAJOR}${KERNELPATCH}${KLOCALVERS}/extra/ 

# Install firmware
ruby "${basedir}/shellscripts/firmwarefinder.rb" ${KERNELPATCH}${KLOCALVERS} targetfs

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
mkdir -p targetfs/etc/bananapi
for t in r1 m1 ; do
	install -m 0644 "${basedir}/configfiles/etc.network.interfaces.${t}" \
		"targetfs/etc/bananapi/network.interfaces.${t}"
done
install -m 0644 "${basedir}/configfiles/etc.if-pre-up.d.swconfig.r1" targetfs/etc/bananapi/if-pre-up.d.swconfig.r1

echo "$PIHOSTNAME" > targetfs/etc/hostname
# FIXME: This seems to fit upstart only
if [ -f "targetfs/etc/init/tty1.conf" ] ; then
	cp -v targetfs/etc/init/{tty1,ttyS0}.conf
	sed -i 's/tty1/ttyS0/g' targetfs/etc/init/ttyS0.conf
fi
# Extra modules
for m in $XTRAMODULES ; do
	echo "${m}" >> targetfs/etc/modules 
done
for m in $BLACKLIST ; do
	echo '' >> targetfs/etc/modprobe.d/blacklist.conf
	echo '# blacklisted by pibuntu script' >> targetfs/etc/modprobe.d/blacklist.conf
	echo "blacklist $m" >> targetfs/etc/modprobe.d/blacklist.conf
done

# Install Pi-Scripts - FIME, move this to a debian package
install -m 0755 "${basedir}/shellscripts/pi-firstrun" targetfs/usr/sbin
install -m 0755 "${basedir}/shellscripts/pi-stretch" targetfs/usr/sbin
install -m 0755 "${basedir}/shellscripts/pi-update" targetfs/usr/sbin
echo '' >> "targetfs/etc/rc.local"
sed -i 's%exit 0%# exit 0%g' "targetfs/etc/rc.local"
echo '/usr/sbin/pi-firstrun' >> "targetfs/etc/rc.local"
echo 'exit 0' >> "targetfs/etc/rc.local"
for f in .stretchfs .stretchpart .firstrun .rundepmod ; do
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

for p in $MINPACKAGES $PIPACKAGES; do
	LC_ALL=POSIX chroot targetfs apt-get -y install $p
done
for p in $PIXTRADEBS ; do
	install -m 0644 ${p} packages/
	LC_ALL=POSIX chroot targetfs dpkg -i /var/cache/apt/archives/` basename $p `
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
# Remove SSH keys
rm -f targetfs/etc/ssh/ssh_host_*

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
