    .section .text.init
    .globl _start
    .type _start, @function

_start:
    addi  s0, zero, 0
    addi  t0, zero, 1

    .rept 64
        beq   zero, zero, 1f
        jal   zero, fail
1:
        bne   zero, zero, fail
        blt   zero, t0, 2f
        jal   zero, fail
2:
        bge   zero, t0, fail
        addi  s0, s0, 1
    .endr

    li    t1, 64
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
