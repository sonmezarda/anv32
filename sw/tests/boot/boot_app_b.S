    # Boot test, second program (sim/tb/soc/tb_soc_boot.sv): sent through the
    # bootloader. Reports with LED = 2 (pass), after checking that its data
    # landed where it was linked.
    .section .text.init
    .globl _start
_start:
    li    t0, 0x10000000        # SYSCTRL LED
    la    t1, magic
    lw    t1, 0(t1)
    li    t2, 0x600DF00D
    bne   t1, t2, 1f
    li    t1, 2
    sw    t1, 0(t0)
1:
    j     1b

    .section .rodata
    .align 2
magic:
    .word 0x600DF00D
