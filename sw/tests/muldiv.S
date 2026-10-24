// RV32M results, including the corner cases from the spec (divide by zero,
// signed overflow) and multi-cycle results used by the next instruction.
#include "test.h"

.macro TRR op, a, b, expected, code
    li      a0, \a
    li      a1, \b
    \op     a2, a0, a1
    CHECK_EQ a2, \expected, \code
.endm

    .section .text.init
    .globl _start
_start:
    TRR div,    0x00000007, 0x00000002, 0x00000003, 10
    TRR div,    0xFFFFFFF9, 0x00000002, 0xFFFFFFFD, 11
    TRR div,    0x00000007, 0xFFFFFFFE, 0xFFFFFFFD, 12
    TRR div,    0xFFFFFFF9, 0xFFFFFFFE, 0x00000003, 13
    TRR div,    0x0000007B, 0x00000000, 0xFFFFFFFF, 14
    TRR div,    0x80000000, 0xFFFFFFFF, 0x80000000, 15
    TRR divu,   0x00000007, 0x00000002, 0x00000003, 16
    TRR divu,   0xFFFFFFFF, 0x00000002, 0x7FFFFFFF, 17
    TRR divu,   0x0000007B, 0x00000000, 0xFFFFFFFF, 18
    TRR divu,   0x80000000, 0xFFFFFFFF, 0x00000000, 19
    TRR rem,    0x00000007, 0x00000002, 0x00000001, 20
    TRR rem,    0xFFFFFFF9, 0x00000002, 0xFFFFFFFF, 21
    TRR rem,    0x00000007, 0xFFFFFFFE, 0x00000001, 22
    TRR rem,    0xFFFFFFF9, 0xFFFFFFFE, 0xFFFFFFFF, 23
    TRR rem,    0x00000005, 0x00000000, 0x00000005, 24
    TRR rem,    0x80000000, 0xFFFFFFFF, 0x00000000, 25
    TRR remu,   0x00000007, 0x00000002, 0x00000001, 26
    TRR remu,   0xFFFFFFFF, 0x0000000A, 0x00000005, 27
    TRR remu,   0x00000005, 0x00000000, 0x00000005, 28
    TRR mul,    0x12345678, 0x9ABCDEF0, 0x242D2080, 29
    TRR mul,    0xFFFFFFFF, 0xFFFFFFFF, 0x00000001, 30
    TRR mul,    0x7FFFFFFF, 0x00000002, 0xFFFFFFFE, 31
    TRR mulh,   0x12345678, 0x9ABCDEF0, 0xF8CC93D6, 32
    TRR mulh,   0xFFFFFFFF, 0xFFFFFFFF, 0x00000000, 33
    TRR mulh,   0x80000000, 0x80000000, 0x40000000, 34
    TRR mulh,   0x7FFFFFFF, 0xFFFFFFFE, 0xFFFFFFFF, 35
    TRR mulhsu, 0x12345678, 0x9ABCDEF0, 0x0B00EA4E, 36
    TRR mulhsu, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 37
    TRR mulhsu, 0x80000000, 0x00000001, 0xFFFFFFFF, 38
    TRR mulhu,  0x12345678, 0x9ABCDEF0, 0x0B00EA4E, 39
    TRR mulhu,  0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFE, 40
    TRR mulhu,  0x80000000, 0x00000002, 0x00000001, 41

    // Dependent chain: each result feeds the next multi-cycle op directly
    li      a0, 1000003
    li      a1, 7
    div     a2, a0, a1                  // 142857
    rem     a3, a2, a1                  // 142857 % 7 = 1
    mul     a4, a2, a1                  // 999999
    add     a4, a4, a3                  // 1000000
    divu    a5, a4, a2                  // 1000000 / 142857 = 7
    CHECK_EQ a2, 142857, 50
    CHECK_EQ a3, 1, 51
    CHECK_EQ a4, 1000000, 52
    CHECK_EQ a5, 7, 53

    // Divisor coming straight from a load
    la      t0, divisor
    lw      t1, 0(t0)
    div     a2, a0, t1
    CHECK_EQ a2, 142857, 54

    // Store right after a divide, then load it back
    la      t0, scratch
    div     a2, a0, a1
    sw      a2, 0(t0)
    lw      a3, 0(t0)
    CHECK_EQ a3, 142857, 55

    TEST_PASS

    .align 2
divisor:
    .word   7
scratch:
    .word   0
