// Illegal instruction traps (mcause, mepc, mtval), including bad CSR
// accesses, and FENCE as a no-op.
#include "test.h"

.macro EXPECT_ILLEGAL word
    la      s1, 97f
    li      s3, \word
97: .word   \word
.endm

    .section .text.init
    .globl _start
_start:
    la      t0, handler
    csrw    mtvec, t0

    EXPECT_ILLEGAL 0x00000000           // all zeros
    EXPECT_ILLEGAL 0xFFFFFFFF           // all ones
    EXPECT_ILLEGAL 0x0000100F           // FENCE.I (Zifencei not implemented)
    EXPECT_ILLEGAL 0x10500073           // WFI (not implemented)
    EXPECT_ILLEGAL 0xFE000033           // OP with funct7 = 0x7F
    EXPECT_ILLEGAL 0x7C002573           // csrr a0, 0x7C0 (no such CSR)
    EXPECT_ILLEGAL 0xF1451073           // csrw mhartid, a0 (read-only)
    EXPECT_ILLEGAL 0xC0051073           // csrw cycle, a0 (read-only)
    EXPECT_ILLEGAL 0xC0102573           // csrr a0, time (not implemented)
    EXPECT_ILLEGAL 0x00100873           // ebreak with rd != 0 (reserved)
    CHECK_EQ s2, 10, 2

    // FENCE must not trap and must not disturb surrounding instructions.
    li      a0, 5
    fence
    addi    a0, a0, 1
    fence   rw, rw
    addi    a0, a0, 1
    CHECK_EQ a0, 7, 3
    CHECK_EQ s2, 10, 4

    TEST_PASS

    .align 4
handler:
    addi    s2, s2, 1
    csrr    t0, mcause
    CHECK_EQ t0, MCAUSE_ILLEGAL, 10
    csrr    t0, mepc
    beq     t0, s1, 1f
    TEST_FAIL 11
1:  csrr    t0, mtval
    beq     t0, s3, 2f
    TEST_FAIL 12
2:  csrr    t0, mepc
    addi    t0, t0, 4
    csrw    mepc, t0
    mret
