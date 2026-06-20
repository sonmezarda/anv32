    .section .text.init
    .globl _start
    .type _start, @function

_start:
    lui   t0, 0x80000
    addi  t0, t0, 0x340

    addi  t1, zero, 9
    addi  t2, t1, 1
    add   t3, t2, t1
    add   t4, t3, t2
    add   t5, t4, t3
    sw    t5, 0(t0)

    lw    s0, 0(t0)
    addi  s1, s0, 1
    add   s2, s1, s0
    sw    s2, 4(t0)

    lw    s3, 4(t0)
    sw    s3, 8(t0)
    lw    s4, 8(t0)

    addi  s5, zero, 0
    beq   s4, s3, load_branch_taken
    addi  s5, zero, 1
load_branch_taken:
    addi  s6, s4, 2

1:
    auipc a0, %pcrel_hi(jalr_target)
    addi  a0, a0, %pcrel_lo(1b)
    sw    a0, 12(t0)
    lw    a1, 12(t0)
    jalr  zero, 0(a1)
jalr_wrong:
    addi  s5, zero, 2

jalr_target:
    lw    a2, 0(t0)
    lw    a3, 4(t0)
    add   a4, a2, a3
    add   a5, a4, a3
    sw    a5, 16(t0)
    lw    a6, 16(t0)

    ebreak
