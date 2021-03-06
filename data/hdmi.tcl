proc sleep {N} {
   after [expr {int($N * 1000)}]
}

proc poll_raise {addr mask} {
    while { [expr {[my_read $addr] & $mask}] == 0x00} {
        sleep 1
        puts "Polling: ($addr = [my_read $addr]) & $mask..."
    }
}

proc my_read {addr} {
    return "0x[string range [mrd $addr] end-8 end-1]"
}

proc my_write {addr val} {
    mwr $addr $val
}

proc iic_select {sel} {
    my_write 0xE0004000 0x3f4e
    my_write 0xE0004010 0xff
    my_write 0xE0004014 0x01
    my_write 0xE000400c $sel
    my_write 0xE0004008 0x74

    poll_raise 0xE0004010 0x01

    my_write 0xE0004000 0x3f4f
    my_write 0xE0004010 0xff
    my_write 0xE0004014 0x01
    #my_write 0xE000400c 0x00
    my_write 0xE0004008 0x74

    poll_raise 0xE0004004 0x20
    puts [format "Seleced: 0x%x" [expr {[my_read 0xe000400c] & 0xff}]]
}

# XXX: This yields always 0x12. Find an I2C ninja to fix it.
proc iic_read { daddr raddr} {
    my_write 0xE0004000 0x3f5e
    my_write 0xE0004010 0xff
    my_write 0xE0004014 0x01
    my_write 0xE000400c $raddr
    my_write 0xE0004008 $daddr

    poll_raise 0xE0004010 0x01

    my_write 0xE0004000 0x3f4f
    my_write 0xE0004010 0xff
    my_write 0xE0004014 0x01
#    my_write 0xE000400c 0x00
    my_write 0xE0004008 $daddr

    poll_raise 0xE0004004 0x20
#    my_write 0xE0004000 0x3f0f
    set ret [expr {[my_read 0xE000400c] & 0xff} ];
    return $ret
}


proc iic_write {daddr waddr wdata} {
    puts "write: *($waddr) <- $wdata"
    my_write 0xE0004000 0x3f4e
    my_write 0xE0004010 0xff
    my_write 0xE0004014 0x02
    my_write 0xE000400c $waddr
    my_write 0xE000400c $wdata
    my_write 0xE0004008 $daddr
    poll_raise 0xE0004010 0x01
    puts "Write success"
    puts [format "btw reading it yields: 0x%x" [iic_read $daddr $waddr]]
}

proc tlcdml_init {} {
    set TLCD_BASEADDR 0x79000000
    puts [format "TLCD magic:(*0x%x) == 0x%x" [expr {$TLCD_BASEADDR + 0xf4}] [my_read [expr {$TLCD_BASEADDR + 0xf4}]]]

    my_write [expr $TLCD_BASEADDR + 0x00] 0x804002c0
    my_write [expr $TLCD_BASEADDR + 0x04] 0x00000401
    my_write [expr $TLCD_BASEADDR + 0x08] 0xffff0000
    my_write [expr $TLCD_BASEADDR + 0x0c] 0x03200258
    my_write [expr $TLCD_BASEADDR + 0x14] 0x03480259
    my_write [expr $TLCD_BASEADDR + 0x18] 0x03c8025d
    my_write [expr $TLCD_BASEADDR + 0x1c] 0x04200274
    my_write [expr $TLCD_BASEADDR + 0x20] 0x00000000
    my_write [expr $TLCD_BASEADDR + 0xf8] 0x00000001
    my_write [expr $TLCD_BASEADDR + 0x30] 0x80ff0006
    my_write [expr $TLCD_BASEADDR + 0x34] 0x00000000
    my_write [expr $TLCD_BASEADDR + 0x38] 0x03200258
    my_write [expr $TLCD_BASEADDR + 0x3c] 0x38000000
    my_write [expr $TLCD_BASEADDR + 0x40] 0x00000c80
    my_write [expr $TLCD_BASEADDR + 0x44] 0x03200258
    my_write [expr $TLCD_BASEADDR + 0x48] 0x00004000
    my_write [expr $TLCD_BASEADDR + 0x4c] 0x00004000
    puts "TLCDML initialized"
}

proc adv_test {} {
    puts "Testing adv"
    iic_write 0x39 0x1C 0xFF
    puts "ADV TEST: Should be 0xff==[iic_read 0x39 0x1C]"

    # puts "Dump regs"
    # for {set i 0} {$i < 20} { incr i} {
    #     puts [format "Register 0x%d => 0x%x" $i [iic_read 0x39 $i]]
    # }
    puts "ADV tested"
}

proc adv7511_init {} {

    puts ""
    puts "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    puts "Programming adv7511..."

    for {set i 0} {$i < 8} { incr i} {
#        puts "Selected [iic_read 0x0 0x74]"

        puts [format "Selecting 0x%x" [expr 1 << $i]]
        iic_select [expr 1 << $i]
    }

    iic_select 0xff
    iic_select 0x2
    # adv_test

    tlcdml_init

    iic_read 0x39 0x96
    iic_write 0x39 0x41 0x10
    iic_write 0x39 0xD6 0xC0
    iic_write 0x39 0x15 0x01
    iic_write 0x39 0x16 0x30
    iic_write 0x39 0x18 0xAB
    iic_write 0x39 0x19 0x37
    iic_write 0x39 0x1A 0x08
    iic_write 0x39 0x1B 0x00
    iic_write 0x39 0x1C 0x00
    iic_write 0x39 0x1D 0x00
    iic_write 0x39 0x1E 0x1A
    iic_write 0x39 0x1F 0x86
    iic_write 0x39 0x20 0x1A
    iic_write 0x39 0x21 0x49
    iic_write 0x39 0x22 0x08
    iic_write 0x39 0x23 0x00
    iic_write 0x39 0x24 0x1D
    iic_write 0x39 0x25 0x3F
    iic_write 0x39 0x26 0x04
    iic_write 0x39 0x27 0x22
    iic_write 0x39 0x28 0x00
    iic_write 0x39 0x29 0x00
    iic_write 0x39 0x2A 0x08
    iic_write 0x39 0x2B 0x00
    iic_write 0x39 0x2C 0x0E
    iic_write 0x39 0x2D 0x2D
    iic_write 0x39 0x2E 0x19
    iic_write 0x39 0x2F 0x14
    iic_write 0x39 0x48 0x08
    iic_write 0x39 0x55 0x00
    iic_write 0x39 0x56 0x28
    iic_write 0x39 0x98 0x03
    iic_write 0x39 0x9A 0xE0
    iic_write 0x39 0x9C 0x30
    iic_write 0x39 0x9D 0x61
    iic_write 0x39 0xA2 0xA4
    iic_write 0x39 0xA3 0xA4
    iic_write 0x39 0xAF 0x04
    iic_write 0x39 0xE0 0xD0
    iic_write 0x39 0xF9 0x00
    puts "Enjoy your turned on screen."
    puts "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
}
