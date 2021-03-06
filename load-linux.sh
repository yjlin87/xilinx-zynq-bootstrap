#!/bin/bash

pathname=$_

# export LD_LIBRARY_PATH=/tools/Xilinx/ISE-SE_Viv-SE/14.4/ISE_DS/EDK/lib/lin64:/tools/Xilinx/ISE-SE_Viv-SE/14.4/ISE_DS/ISE/lib/lin64
# export XILINX=/tools/Xilinx/ISE-SE_Viv-SE/14.4/ISE_DS/ISE
# export XILINX_EDK=/tools/Xilinx/ISE-SE_Viv-SE/14.4/ISE_DS/EDK
# export XILINXD_LICENSE_FILE=/tools/licenses/Xilinx_Zynq-7000_EPP_ZC702_IMAGEON_gray.lic

# XLNX=/opt/Xilinx/14.4
# export XILINX=${XILINX:-$XLNX/ISE_DS/ISE}
# export XILINX_EDK=${XILINX_EDK:-$XLNX/ISE_DS/EDK}
# XILINX_BIN_PATH=$XLNX/ISE_DS/EDK/bin/lin
# XILINX_BIN_PATH64=$XLNX/ISE_DS/EDK/bin/lin64

# REMOTE_XMD=${REMOTE_XMD:-"ssh cperivol@grey"}
# XMD=${XMD:-$XILINX_EDK/bin/lin64/xmd}
XMD=/opt/Xilinx/SDK/2014.1/bin/xmd

function eecho {
   echo "$@" 1>&2;
}

function fail {
    eecho "[ERROR] $1";
    exit 1;
}

read -d '' HELP_MESSAGE <<EOF

This program loads your software to the board. I assume the current
directory is at the root of the project and bootstrap.sh was run
successfully.

OPTIONS:
--reset		Reset the device

--minicom	Only run minicom.

--xmd-shell 	Run an xmd shell. Try to have readline with rlwrap.  It is
recommended to run xmd from here anyway as it will try
to correct your xmd executable aswell

EOF

LOG_FILE="load-linux.log"

# Defaults
load_bitstream='y'
load_uimage='y'
load_ramdisk=''
no_boot=''
run_minicom='y'

iface="eth0"
clientip="192.168.1.50"

function kill_xmd {
    # Get the xmd executable
    if [ -n "$REMOTE_XMD" ]; then
        # ssh -n means dont steal the standard input.
	open_xmd="$(eval $REMOTE_XMD -n pgrep xmd)"
        xmd_usr="$(eval $REMOTE_XMD -n ps aux | awk '($2 == $open_xmd){print $1}')"
    else
	open_xmd="$(pgrep xmd)"
        xmd_usr="$(ps aux | awk '($2 == $open_xmd){print $1}')"
    fi

    if [ -n "$open_xmd" ]; then
        kill_cmd="$REMOTE_XMD kill $open_xmd"
    	echo "Looks like another xmd is running with pid=$open_xmd and user: $xmd_usr."
        echo "Killing with: $kill_cmd"
        eval $kill_cmd
    fi
}

# Select and run xmd, with --print show the command.
function ll_xmd {
    mode="$1"
    kill_xmd

    # Find a proper xmd
    if [ -n "$XMD" ]; then
    	[ ! "$mode" = "--print" ] && echo "XMD setup to '$XMD'";
    elif [ -d $XILINX_BIN_PATH64 ] && [ $(uname -p) = 'x86_64' ]; then
    	XMD=$XILINX_BIN_PATH64/xmd
    elif [ -d $XILINX_BIN_PATH ]; then
    	XMD=$XILINX_BIN_PATH/xmd
    else
    	echo "Failed to find xmd at $XILINX_BIN_PATH64 and $XILINX_BIN_PATH, trying \$PATH"
    	# Try the PATH
    	XMD=$(which xmd)
    fi

    if [ -z "$XMD" ]; then
	fail "No xmd found."
    fi

    case "$mode" in
	"--print")
	    echo "$REMOTE_XMD $XMD";;
	"--interactive")
	    eval "$REMOTE_XMD $XMD";;
	*)
            pipe="/tmp/xmd_pipe$(date +%s)"
	    mkfifo -m 777 "$pipe"
            (cat $pipe | eval "$REMOTE_XMD $XMD") &
            trap "kill_xmd" 2
            tee $pipe
            wait
	    rm "$pipe";;
    esac;
}

# Pipe here what you need in the serial, with --print just show the device
function ll_serial
{
    print_p="$1"

    if [ ! $SERIAL ]; then
	SERIAL=$( ls -d /dev/* | grep ttyUSB | tac | head -1 )
    fi


    if [ -z "$SERIAL" ] || [ ! -c $SERIAL ]; then
	fail "No serial port found or the provided is invalid."
    fi

    [ ! -w $SERIAL ] && fail "Serial $SERIAL is not writeable. Try 'sudo chmod a+rw $SERIAL'"

    if [ "$print_p" = "--print" ]; then
	echo "$SERIAL"
    else
	while read cmd; do
	    echo "$cmd" | tr '\n' '; ' | tee > "$SERIAL"
	    sleep 0.5;
	done
	echo -e "\n" > "$SERIAL"
    fi
}

function xmd_shell
{
    ll_xmd --print
    if [ $(command -v rlwrap) ]; then
	echo "Using rlwrap for history and completion, you are welcome."
        rlwrap -c $(ll_xmd --print)
    else
	echo "rlwrap not found, running plain xmd"
	ll_xmd --interactive
    fi
}

function reset_device
{
    echo "echo \"Device reset commanded by $(whoami)!\""  | ll_serial
    echo -e "connect arm hw\ntarget 64\nrst" | ll_xmd
    echo  "Device reset!"
}

function print_xmd_commands
{
    resources=$(pwd)/drafts
    if ! [[ -d $resources ]]; then
	fail "No `pwd`/resources/ dir found."
    fi

    uimage=$resources/uImage
    ramdisk=$resources/uramdisk.image.gz
    dtb=$resources/devicetree.dtb
    ubootelf=$resources/u-boot.elf
    ps7_init_tcl=$resources/ps7_init.tcl
    stub_tcl=$resources/stub.tcl
    hdmi_setup_tcl=$resources/hdmi.tcl
    boot_bin=$resources/BOOT.bin


    if [ -n "$load_bitstream" ]; then
	bitstream=$resources/bitstream.bit
	echo "fpga -f $bitstream"
    fi

    echo "connect arm hw"
    echo -e "source $ps7_init_tcl\nps7_init\nps7_post_config\ninit_user"
    echo -e "source $stub_tcl\ntarget 64"
    echo -e "source $hdmi_setup_tcl\nadv7511_init"

   # echo "dow -data $boot_bin 0x08000000"
    echo -e "dow $ubootelf"

    if [ -n "$load_uimage" ]; then
	echo "dow -data $uimage	0x30000000"
    fi

    if [ -n "$load_ramdisk" ]; then
	echo "dow -data $ramdisk	$ramdisk_addr"
    fi

    if [ -n "$load_devtree" ]; then
	echo "dow -data $dtb		0x2A000000"
    fi

    echo -e "$extra_xmd\ncon";
}

function minicom {
    MINICOM_CMD="/usr/bin/minicom -D $(ll_serial --print) -b 115200"
    echo "Running $MINICOM_CMD"
    $MINICOM_CMD
}

if [ -n "$load_ramdisk" ]; then
    ramdisk_addr="0x20000000"
else
    ramdisk_addr="-"
fi


function load_linux {
    print_xmd_commands | ll_xmd || fail "sending images to device"
}

function uboot_commands {
    eecho "Stopping autoboot!"
    echo ""
    echo "env default -a"
    echo "setenv autoload no"			# Stop a possible autoboot
    # echo "setenv ethaddr $(python -c "import random; print ':'.join([hex(random.randint(0,0x100))[-2:] for _ in range(6)])")"
    # echo "setenv ethaddr 00:0a:35:00:01:22" # the default one
    echo "setenv ethaddr 29:2f:ad:f9:67:6e" # a random one that works
    if [ -n "$bootargs" ]; then
	echo "setenv bootargs $bootargs"
    fi

    if [ -n "$tftp_load" ]; then
	hostip=$(ifconfig $iface | awk '($1=="inet"){split($2, ip, ":"); print ip[2]}')

	if [ -n "$clientip" ]; then
	    echo "setenv ipaddr $clientip"
	else
	    echo  "dhcp"
	fi
	echo "setenv serverip $hostip"
	echo "tftpboot 0x30000000 uImage"
	echo "tftpboot 0x2a000000 devicetree.dtb"
    fi

    echo "bootm 0x30000000 $ramdisk_addr 0x2A000000"
}

function main
{
    echo "Beginning Script" > $LOG_FILE
    load_linux

    if [ -z "$no_boot" ];  then
	#	sleep 5
	uboot_commands | ll_serial
    fi
    echo "Ending Script" > $LOG_FILE

    if [ -n "$run_minicom" ]; then
	minicom
    fi
}

if ! [ $pathname = $0 ]; then
    while [[ $# -gt 0 ]]; do
        case $1 in
	    '--reset')
                echo "Resetting device..."
	        reset_device;
	        exit 0;;
	    '--minicom')
	        minicom;
	        exit 0;;
	    '--which-serial')
	        ll_serial --print;
	        exit 0;;
	    '--which-xmd')
	        ll_xmd --print
	        exit 0;;
	    '--xmd-shell')
	        xmd_shell;
	        exit 0;;
	    '--show-xmd-commands')
	        print_xmd_commands;
	        exit 0;;
	    '--bootargs')
	        shift; bootargs="$1";;
	    '--xmd-extra')
	        shift; extra_xmd="$1";;
	    '--no-boot')
	        no_boot="y";;
	    '--no-bitstream')
	        load_bitstream='';;
	    '--no-minicom')
	        run_minicom="";;
	    '--no-ramdisk')
	        load_ramdisk="";;
	    '--no-linux')
	        load_linux='';;
	    "--no-devtree")
	        load_devtree='';;
	    '--with-minicom')
	        run_minicom="y";;
	    '--with-ramdisk')
	        load_ramdisk="y";;
	    '--with-linux')
	        load_uimage='y';;
	    "--with-devtree")
	        load_devtree='y';;
	    "--tftp")
	        tftp_load="y";
	        load_devtree="";
	        load_uimage="";
	        load_ramdisk="";;
	    '--help')
	        echo "$HELP_MESSAGE"
	        exit 0;;
	    *)
	        echo "Unrecognized option \"$1\"";
	        exit 1;;
        esac
        shift
    done

    main
fi
