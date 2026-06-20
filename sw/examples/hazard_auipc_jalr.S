    .section .text.init
    .globl _start
    .type _start, @function

_start:
1:
    auipc ra, %pcrel_hi(target)
    jalr  ra, %pcrel_lo(1b)(ra)

wrong_path_0:
    addi  t0, zero, 1
wrong_path_1:
    addi  t0, zero, 2
    ebreak

target:
    addi  t1, zero, 0x2a
    ebreak
