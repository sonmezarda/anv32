    .section .text.init
    .globl _start
    .type _start, @function

_start:
    addi  t0, zero, 96
    addi  s0, zero, 0

1:
    addi  s0, s0, 1

    beq   s0, s0, 2f
    jal   zero, fail
2:
    blt   zero, s0, 3f
    jal   zero, fail
3:
    bgeu  s0, zero, 4f
    jal   zero, fail
4:
    addi  t0, t0, -1
    bne   t0, zero, 1b

    li    t1, 96
    bne   s0, t1, fail
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
