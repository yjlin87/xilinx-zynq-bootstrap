#!/bin/bash
#
# Copyright (C) 2013 by Chris "fakedrake" Perivolaropoulos
# <darksaga2006@gmail.co,>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# TODO:
# - Turn this into a makefile
# - Gnu Toolchain: either ask for a path to the gnu tools
# - Rest of the code

ROOT_DIR=`pwd`
RESOURCES_DIR=$ROOT_DIR/resources
FILESYSTEM_ROOT=$ROOT_DIR/fs/

if [ ! -d $RESOURCES_DIR ]; then
    mkdir $RESOURCES_DIR
fi

# Git repos
LINUX_GIT="git://git.xilinx.com/linux-xlnx.git"
BUSYBOX_GIT="git://git.busybox.net/busybox"
UBOOT_GIT="git://git.xilinx.com/u-boot-xlnx.git"

# What not to build
BUILD_LINUX="true"
BUILD_DROPBEAR="true"
BUILD_BUSYBOX="true"
BUILD_UBOOT="true"
BUILD_RAMDISK="true"

# Device trees
DTS_TREE=$ROOT_DIR/linux-xlnx/arch/arm/boot/dts/zynq-zc702.dts
DTD_TREE=$RESOURCES_DIR/`basename $DTS_TREE | tr '.dts' '.dtd'`

# Dropbear download info
DROPBEAR_TAR_URL="http://matt.ucc.asn.au/dropbear/releases/dropbear-0.53.1.tar.gz"
DROPBEAR_TAR=`basename $DROPBEAR_TAR_URL`

GNU_TOOLS="`pwd`/GNU_Tools/"

for i in $@; do
    case $i in
	"--no-linux") BUILD_LINUX="false";;
	"--no-dropbear") BUILD_DROPBEAR="false";;
	"--no-busybox") BUILD_BUSYBOX="false";;
	"--no-ramdisk") BUILD_RAMDISK="false";;
	"--no-u-boot") BUILD_UBOOT="false";;
	"--gnu-tools")
	    shift
	    GNU_TOOLS=`realpath $1`
	    ;;
	"--help")
	    echo $HELP_MESSAGE
	    exit 0;;
    esac
done

# Dependent vars
GNU_TOOLS_UTILS=$GNU_TOOLS/arm-xilinx-linux-gnueabi/
GNU_TOOLS_BIN=$GNU_TOOLS/bin
GNU_TOOLS_PREFIX=$GNU_TOOLS_BIN/arm-xilinx-linux-gnueabi-
CROSS_COMPILE=$GNU_TOOLS_PREFIX

function print_info {
    echo "[INFO] $1"
}

function get_project {
    if [ ! -d $1 ]; then
	print_info "Cloning $1: $2"
	git clone $2 $1
	cd "$1"
    else
	print_info "Updating $1"
	cd "$1"
	git pull
    fi
}

# Gnu toolchain
if [ ! -d $GNU_TOOLS ]; then
    print_info "The directory '$GNU_TOOLS' should contain the gnu tools."
    echo "(You may use --gnu-tools <dirname> to use your own directory)"
fi

 # U-Boot
if [ $BUILD_UBOOT == "true" ]; then
    cd $ROOT_DIR
    get_project u-boot-xlinx $UBOOT_GIT
    print_info "Configuring uboot."
    make zynq_zc70x_config
    print_info "Building uboot."
    make
fi

# Linux
if [ $BUILD_LINUX == "true" ]; then
    cd $ROOT_DIR
    get_project linux-xlnx $LINUX_GIT
    print_info "Configuring the Linux Kernel"
    make ARCH=arm xilinx_zynq_defconfig
    print_info "Building the linux kernel."
    make ARCH=arm uImage
    print_info "Building device tree"
    scripts/dtc/dtc -I dts -O dtb -o $DTS_TREE $DTD_TREE
    cp $ROOT_DIR/linux-xlnx/arch/arm/boot/uImage $RESOURCES_DIR
else
    print_info "Skipping linux compilation."
fi


# Filsystem/Busybox
if [ $BUILD_BUSYBOX == "true" ]; then
    cd $ROOT_DIR
    if [ ! -d $FILESYSTEM_ROOT ]; then
	mkdir $FILESYSTEM_ROOT
    fi

    get_project busybox $BUSYBOX_GIT

    print_info "Building filesystem"
    make ARCH=arm CROSS_COMPILE=$GNU_TOOLS_PREFIX CONFIG_PREFIX="$FILESYSTEM_ROOT" defconfig
    make ARCH=arm CROSS_COMPILE=$GNU_TOOLS_PREFIX CONFIG_PREFIX="$FILESYSTEM_ROOT" install

    cd $FILESYSTEM_ROOT
    cp $GNU_TOOLS/libc/lib/* lib -r

    # Strip libs of symbols
    $GNU_TOOLS_BIN/arm-xilinx-linux-gnueabi-strip lib/*

    # Some supplied tools
    cp $GNU_TOOLS_UTILS/libc/sbin/* sbin/ -r
    cp $GNU_TOOLS_UTILS/libc/usr/bin/* usr/bin/ -r

    # Create fs structure
    mkdir dev etc etc/dropbear etc/init.d mnt opt proc root sys tmp var var/log var/www

    # Specific files
    echo "LABEL=/     /           tmpfs   defaults        0 0
none        /dev/pts    devpts  gid=5,mode=620  0 0
none        /proc       proc    defaults        0 0
none        /sys        sysfs   defaults        0 0
none        /tmp        tmpfs   defaults        0 0" > etc/fstab

    echo "::sysinit:/etc/init.d/rcS

# /bin/ash
#
# Start an askfirst shell on the serial ports

ttyPS0::respawn:-/bin/ash

# What to do when restarting the init process

::restart:/sbin/init

# What to do before rebooting

::shutdown:/bin/umount -a -r" > etc/inittab

    echo "root:$1$qC.CEbjC$SVJyqm.IG.gkElhaeM.FD0:0:0:root:/root:/bin/sh" > etc/passwd

    echo '#!/bin/sh

echo "Starting rcS..."

echo "++ Mounting filesystem"
mount -t proc none /proc
mount -t sysfs none /sys
mount -t tmpfs none /tmp

echo "++ Setting up mdev"

echo /sbin/mdev > /proc/sys/kernel/hotplug
mdev -s

mkdir -p /dev/pts
mkdir -p /dev/i2c
mount -t devpts devpts /dev/pts

echo "++ Starting telnet daemon"
telnetd -l /bin/sh

echo "++ Starting http daemon"
httpd -h /var/www

echo "++ Starting ftp daemon"
tcpsvd 0:21 ftpd ftpd -w /&

echo "++ Starting dropbear (ssh) daemon"
dropbear

echo "rcS Complete"' > etc/init.d/rcS

    chmod 755 etc/init.d/rcS
    sudo chown root:root etc/init.d/rcS # I dont think this is necessary
else
    print_info "Skipping busybox compilation and filesystem creation."
fi

# Dropbear
if [ $BUILD_DROPBEAR == "true" ]; then
    cd $ROOT_DIR
    if [ ! -d $ROOT_DIR/dropbear/ ]; then
	mkdir $ROOT_DIR/dropbear
	print_info "Downloading dropbear"
	wget $DROPBEAR_TAR_URL -O $ROOT_DIR/$DROPBEAR_TAR
	echo "Uncompressing: tar xfvz $ROOT_DIR/$DROPBEAR_TAR -C $ROOT_DIR/dropbear/"
	tar xfvz $ROOT_DIR/$DROPBEAR_TAR -C $ROOT_DIR/dropbear/
	rm $ROOT_DIR/$DROPBEAR_TAR
    fi

    print_info "Building dropbear"
    cd $ROOT_DIR/dropbear/*/
    ./configure --prefix=$FILESYSTEM_ROOT --host=$GNU_TOOLS_PREFIX --disable-zlib CC=arm-xilinx-linux-gnueabi-gcc LDFLAGS="-Wl,--gc-sections" CFLAGS="-ffunction-sections -fdata-sections -Os"
    make PROGRAMS="dropbear dbclient dropbearkey dropbearconvert scp" MULTI=1 strip
    sudo make install;		# Thre are some `chgrp 0' here so we need sudo

    ln -s ../../sbin/dropbear $FILESYSTEM_ROOT/usr/bin/scp
else
    print_info "Skipping dropbear compilation"
fi

# Build ramdisk image
if [ $BUILD_RAMDISK == "true" ]; then
    cd $RESOURCES_DIR
    # Build ramdisk image
    dd if=/dev/zero of=ramdisk.img bs=1024 count=8192
    mke2fs -F ramdisk.img -L "ramdisk" -b 1024 -m 0
    tune2fs ramdisk.img -i 0
    chmod 777 ramdisk.img

    mkdir ramdisk
    sudo mount -o loop ramdisk.img ramdisk/
    sudo cp -R $FILESYSTEM_ROOT/* ramdisk
    sudo umount ramdisk/

    gzip -9 ramdisk.img

    # U-Boot ready image
    $ROOT_DIR/u-boot-xlinx/mkimage –A arm –T ramdisk –C gzip –d ramdisk.img.gz uramdisk.img.gz
else
    print_info "Skipping ramdisk creation."
fi
