#!/bin/bash

SERIAL=/dev/ttyUSB0

if [ $1 = "stop" ]; then
    echo -e "connect arm hw\nstop" | xmd
    exit 1
fi

if [[ -d resources/ ]]; then
    cd resources/
    echo "In directory: `pwd`"
else
    echo "No `pwd`/resources/ dir found."
    exit 0
fi

echo "connect arm hw
source ps7_init.tcl
ps7_init
init_user
source stub.tcl
target 64
dow -data uImage            0x30000000
dow -data uramdisk.img.gz   0x20000000
dow -data zynq-zc702.dtd    0x2A000000
dow u-boot.elf
con
" | xmd && sleep 1 && echo -e "\n" > $SERIAL && sleep 2 && echo "bootm 0x30000000 0x20000000 0x2A000000" > $SERIAL


if [ "$1" = "minicom" ]; then
    echo "Running sudo minicom -D /dev/ttyUSB0 -b 115200"
fi
