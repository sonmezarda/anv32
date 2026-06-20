    .section .text.init
    .globl _start
    .type _start, @function

_start:
    addi  x1, zero, 0x15
    addi  x2, zero, 0x20
    addi  x3, x2, 0x10
    addi  x4, x2, 0x20
    add   x5, x3, x4
    add   x6, x3, x4

    ebreak
