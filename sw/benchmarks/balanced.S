    .section .text.init
    .globl _start
    .type _start, @function

_start:
    la    t0, balanced_data
    addi  t1, zero, 0
    addi  t2, zero, 64

1:
    lw    t3, 0(t0)
    add   t1, t1, t3
    xor   t4, t2, t3
    xor   t4, t4, t2
    bne   t4, t3, fail

    andi  t5, t2, 1
    beq   t5, zero, 2f
    addi  t1, t1, 2
    jal   zero, 3f
2:
    addi  t1, t1, 1
3:
    sw    t1, 0(t0)
    addi  t0, t0, 4
    addi  t2, t2, -1
    bne   t2, zero, 1b

    li    t6, 160
    bne   t1, t6, fail
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

    .section .data
    .balign 4
balanced_data:
    .rept 64
        .word 1
    .endr
