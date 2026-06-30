    .section .text.init
    .globl _start
    .type _start, @function

_start:
    la    t0, bench_data
    addi  t1, zero, 0
    addi  t2, zero, 64

1:
    sw    t1, 0(t0)
    lw    t3, 0(t0)
    bne   t3, t1, fail

    addi  t1, t1, 3
    addi  t0, t0, 4
    addi  t2, t2, -1
    bne   t2, zero, 1b

    li    t4, 192
    bne   t1, t4, fail
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
bench_data:
    .space 256
