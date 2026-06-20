    .section .text.init
    .globl _start
    .type _start, @function

_start:
    addi  x1, zero, -1
    addi  x2, zero, 1
    addi  x3, zero, 31

    slli  x4, x2, 31
    srli  x5, x4, 31
    srai  x6, x4, 31

    slt   x7, x1, x2
    sltu  x8, x1, x2
    slti  x9, x1, 0
    sltiu x10, x1, 1

    add   x11, x4, x1
    sub   x12, x4, x2
    xor   x13, x11, x12
    or    x14, x11, x12
    and   x15, x11, x12

    sll   x16, x2, x3
    srl   x17, x16, x3
    sra   x18, x16, x3

    lui   x19, 0x12345
    addi  x19, x19, 0x678
    xori  x20, x19, -1
    ori   x21, x20, 0x055
    andi  x22, x21, 0x0f0

    addi  x0, zero, 123
    addi  x23, x0, 5

    auipc x24, 0
    addi  x25, x24, 16
    sub   x26, x25, x24

    ebreak
