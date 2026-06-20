    .section .text.init
    .globl _start
    .type _start, @function

_start:
    lui   t0, 0x80000
    addi  t0, t0, 0x300

    lui   t1, 0x807ff
    addi  t1, t1, -255      # 0x807fe_f01
    sw    t1, 0(t0)
    lw    t2, 0(t0)

    lb    s0, 0(t0)
    lb    s1, 1(t0)
    lbu   s2, 1(t0)
    lh    s3, 2(t0)
    lhu   s4, 2(t0)

    addi  t3, zero, -128
    sb    t3, 4(t0)
    lbu   s5, 4(t0)
    lb    s6, 4(t0)

    addi  t4, zero, -2
    sh    t4, 6(t0)
    lhu   s7, 6(t0)
    lh    s8, 6(t0)

    addi  t5, zero, 0x12
    sb    t5, 5(t0)
    lw    s9, 4(t0)

    addi  t6, zero, 0x7f
    sb    t6, 9(t0)
    lb    s10, 9(t0)
    lbu   s11, 9(t0)

    ebreak
