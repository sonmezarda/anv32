    .section .text.init
    .globl _start
    .type _start, @function

_start:
    addi  s0, zero, 0
    addi  t0, zero, 1

    .rept 128
        beq   s0, t0, fail
        bne   s0, s0, fail
        blt   t0, s0, fail
        bgeu  s0, t0, fail
        addi  s0, s0, 1
        addi  t0, t0, 1
    .endr

    li    t1, 128
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
