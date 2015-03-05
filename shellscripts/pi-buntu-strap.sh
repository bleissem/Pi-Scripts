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
# PITARGET=/dev/sdc # Path to a block device or name of a file 
# PISIZE=4000000000 # Size of the image to create, will be rounded down to full MB
# PIHOSTNAME=pibuntu # Hostname to use
# PIUSER=mattias # Create an unprivileged user - leave empty to skip
#
# IGNOREDPKG=1 # Use after installing debootstrap on non Debian OS

me=` id -u `
if [ "$me" -gt 0 ] ; then
	echo 'Please run this script with root privileges!'
	exit 1
fi

# Check the architecture we are running on

case ` uname -m ` in
	armv7l )
		echo "OK, running on ARMv7..."
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
	echo ':-( Dpkg was not found, if you are running on non-debian, install debootstrap manually'
	exit 1
fi

# Check for more programs

progsneeded="gcc bc patch make mkimage git wget"
for p in $progsneeded ; do
	echo "$p is missing. Please install dependencies:"
	echo "apt-get install bc libncurses5-dev build-essential u-boot-tools git wget"
	exit 1
done



