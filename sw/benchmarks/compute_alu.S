    .section .text.init
    .globl _start
    .type _start, @function

_start:
    li    t0, 0x13579bdf
    li    t1, 0x2468ace0
    li    t2, 64
    addi  s0, zero, 0

1:
    add   s1, t0, t1
    sub   s1, s1, t1
    bne   s1, t0, fail

    xor   s2, t0, t1
    xor   s2, s2, t1
    bne   s2, t0, fail

    slli  s3, t0, 4
    srli  s3, s3, 4
    li    s4, 0x03579bdf
    bne   s3, s4, fail

    li    s5, -8
    srai  s5, s5, 1
    li    s6, -4
    bne   s5, s6, fail

    slt   a1, zero, t0
    sltu  a2, t0, t1
    and   a3, a1, a2
    bne   a3, a1, fail

    ori   a4, t0, 0x0f0
    andi  a4, a4, 0x0f0
    li    a5, 0x0f0
    bne   a4, a5, fail

    addi  s0, s0, 1
    addi  t2, t2, -1
    bne   t2, zero, 1b

    li    t3, 64
    bne   s0, t3, fail
    jal   zero, pass

pass:
    addi  a0, zero, 1
    addi  zero, zero, 0
    addi  zero, zero, 0
    addi  zero, zero, 0
    ebreak

fail:
    addi  a0, zero, 0
    addi  zero, zero, 0
    addi  zero, zero, 0
    addi  zero, zero, 0
    ebreak
