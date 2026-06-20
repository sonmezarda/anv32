    .section .text.init
    .globl _start
    .type _start, @function

_start:
    lui   t0, 0x80000
    addi  t0, t0, 0x100
    lui   t1, 0x80800
    addi  t1, t1, -255      # t1 = 0x807fff01
    sw    t1, 0(t0)

    lb    t2, 1(t0)         # expected 0xffffffff
    addi  s0, zero, 0x33

    lbu   s1, 3(t0)         # expected 0x00000080
    addi  s2, zero, 0x44

    lh    s3, 2(t0)         # expected 0xffff807f
    addi  s4, zero, 0x55

    lhu   s5, 2(t0)         # expected 0x0000807f
    addi  s6, zero, 0x66

    lw    s7, 0(t0)         # expected 0x807fff01
    addi  s8, zero, 0x77

    ebreak
