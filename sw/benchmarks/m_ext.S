    .section .text.init
    .globl _start
    .type _start, @function

_start:
    addi  t0, zero, 16
    addi  s0, zero, 0

1:
    li    t1, 7
    li    t2, 11
    mul   t3, t1, t2
    li    t4, 77
    bne   t3, t4, fail

    div   t5, t3, t1
    bne   t5, t2, fail

    rem   t6, t3, t1
    bne   t6, zero, fail

    mulh  a1, t1, t2
    bne   a1, zero, fail

    addi  s0, s0, 1
    addi  t0, t0, -1
    bne   t0, zero, 1b

    li    a2, 16
    bne   s0, a2, fail
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
