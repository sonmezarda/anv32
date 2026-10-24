// Loads and stores of every width and byte offset, sign extension, and
// back-to-back store/load and load/store pairs.
#include "test.h"

    .section .text.init
    .globl _start
_start:
    la      s0, src                     // 0x80FF7F01

    lb      a0, 0(s0)
    CHECK_EQ a0, 0x00000001, 2
    lb      a0, 1(s0)
    CHECK_EQ a0, 0x0000007F, 3
    lb      a0, 2(s0)
    CHECK_EQ a0, 0xFFFFFFFF, 4
    lb      a0, 3(s0)
    CHECK_EQ a0, 0xFFFFFF80, 5
    lbu     a0, 2(s0)
    CHECK_EQ a0, 0x000000FF, 6
    lbu     a0, 3(s0)
    CHECK_EQ a0, 0x00000080, 7
    lh      a0, 0(s0)
    CHECK_EQ a0, 0x00007F01, 8
    lh      a0, 2(s0)
    CHECK_EQ a0, 0xFFFF80FF, 9
    lhu     a0, 2(s0)
    CHECK_EQ a0, 0x000080FF, 10
    lw      a0, 0(s0)
    CHECK_EQ a0, 0x80FF7F01, 11

    // Negative offset
    la      s1, dst
    lw      a0, -4(s1)
    CHECK_EQ a0, 0x80FF7F01, 12

    // Partial stores into one word
    sw      zero, 0(s1)
    li      a1, 0xAA
    sb      a1, 1(s1)
    li      a1, 0xBBCC
    sh      a1, 2(s1)
    li      a1, 0x11
    sb      a1, 0(s1)
    lw      a0, 0(s1)
    CHECK_EQ a0, 0xBBCCAA11, 13
    lbu     a0, 3(s1)
    CHECK_EQ a0, 0xBB, 14

    // Store then load the same address immediately
    li      a1, 0x12345678
    sw      a1, 4(s1)
    lw      a0, 4(s1)
    CHECK_EQ a0, 0x12345678, 15

    // Loaded value stored by the next instruction
    lw      a2, 0(s0)
    sw      a2, 8(s1)
    lw      a0, 8(s1)
    CHECK_EQ a0, 0x80FF7F01, 16

    // Load result used as the next load's address
    la      a1, ptr
    lw      a2, 0(a1)
    lw      a0, 0(a2)
    CHECK_EQ a0, 0x80FF7F01, 17

    // Back-to-back loads of different values, repeated so random wait
    // states hit every position. Each value must reach its own register.
    la      s2, table
    li      s3, 32                      // passes
    li      s4, 0                       // checksum
1:  lw      a0, 0(s2)
    lw      a1, 4(s2)
    lw      a2, 8(s2)
    lw      a3, 12(s2)
    lbu     a4, 1(s2)
    lhu     a5, 6(s2)
    add     s4, s4, a0
    xor     s4, s4, a1
    add     s4, s4, a2
    xor     s4, s4, a3
    add     s4, s4, a4
    add     s4, s4, a5
    addi    s3, s3, -1
    bnez    s3, 1b
    CHECK_EQ s4, 0x39771600, 18

    TEST_PASS

    .align 2
table:
    .word   0x11111111, 0x22222222, 0x44444444, 0x88888888
src:
    .word   0x80FF7F01
dst:
    .word   0, 0, 0
ptr:
    .word   src
