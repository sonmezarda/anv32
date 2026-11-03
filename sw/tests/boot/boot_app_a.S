    # Boot test, first program (sim/tb/soc/tb_soc_boot.sv): in the BRAM image
    # from the start. Tries to overwrite the bootloader, through its address
    # and through the BRAM alias 32 KiB up, then reports with LED = 3.
    .section .text.init
    .globl _start
_start:
    li    t0, 0x10000000        # SYSCTRL LED
    li    t1, 0xDEADBEEF
    li    t2, 0x7C00            # bootloader
    sw    t1, 0(t2)
    sw    t1, 0x100(t2)
    li    t2, 0xFC00            # same, through the wrap of the 64 KiB BRAM region
    sw    t1, 0(t2)
    li    t1, 3
    sw    t1, 0(t0)
1:
    j     1b
