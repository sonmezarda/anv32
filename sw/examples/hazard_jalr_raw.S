    .section .text.init
    .globl _start
    .type _start, @function

_start:
    addi  ra, zero, 0x14
    jalr  zero, 0(ra)

wrong_path_0:
    addi  t0, zero, 1
wrong_path_1:
    addi  t0, zero, 2
    ebreak

    .org 0x14
target:
    addi  t1, zero, 0x2a
    ebreak
