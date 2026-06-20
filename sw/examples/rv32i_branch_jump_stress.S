    .section .text.init
    .globl _start
    .type _start, @function

_start:
    addi  t0, zero, 7
    addi  t1, zero, 7
    beq   t0, t1, beq_taken
    addi  s0, zero, 1
beq_taken:
    addi  s1, zero, 0x11

    addi  t2, zero, -1
    addi  t3, zero, 1
    blt   t2, t3, blt_taken
    addi  s0, zero, 2
blt_taken:
    addi  s2, zero, 0x22

    bltu  t3, t2, bltu_taken
    addi  s0, zero, 3
bltu_taken:
    addi  s3, zero, 0x33

    bne   t0, t1, bne_wrong
    addi  s4, zero, 0x44
    jal   ra, jal_target
bne_wrong:
    addi  s0, zero, 4

jal_wrong_0:
    addi  s0, zero, 5
jal_target:
    addi  s5, ra, 0

1:
    auipc t4, %pcrel_hi(jalr_target)
    jalr  t5, %pcrel_lo(1b)(t4)
jalr_wrong_0:
    addi  s0, zero, 6
jalr_wrong_1:
    addi  s0, zero, 7

jalr_target:
    addi  s6, t5, 0

    addi  t0, zero, 5
    addi  t1, zero, 6
    bge   t1, t0, bge_taken
    addi  s0, zero, 8
bge_taken:
    bgeu  t1, t0, bgeu_taken
    addi  s0, zero, 9
bgeu_taken:
    addi  s7, zero, 0x77

    ebreak
