// External interrupt basics: masking by mstatus.MIE and mie.MEIE, trap CSRs,
// and that enabling a pending interrupt traps right after the enabling
// instruction.
//
// The handler only touches a0/a1 (plus t5/t6 in the macros), so it can
// interrupt the SPIN loop, which counts in t0.
#include "test.h"

.macro SPIN n
    li      t0, \n
1:  addi    t0, t0, -1
    bnez    t0, 1b
.endm

    .section .text.init
    .globl _start
_start:
    la      t0, handler
    csrw    mtvec, t0

    // Pending, MEIE = 1, MIE = 0: not taken
    li      t0, MIE_MEIE
    csrw    mie, t0
    IRQ_AFTER 0
    SPIN    40
    CHECK_EQ s2, 0, 2

    // Pending, MIE = 1, MEIE = 0: not taken
    csrw    mie, zero
    csrsi   mstatus, MSTATUS_MIE
    SPIN    40
    CHECK_EQ s2, 0, 3

    // Setting MEIE traps before the next instruction
    li      t0, MIE_MEIE
    la      s1, after_mie
    csrw    mie, t0
after_mie:
    addi    s3, s3, 1
    CHECK_EQ s2, 1, 4
    CHECK_EQ s3, 1, 5                   // the instruction ran exactly once

    // Same with MIE: pending while disabled, taken right after csrsi
    csrci   mstatus, MSTATUS_MIE
    IRQ_AFTER 0
    SPIN    20
    CHECK_EQ s2, 1, 6
    la      s1, after_mstatus
    csrsi   mstatus, MSTATUS_MIE
after_mstatus:
    addi    s3, s3, 1
    CHECK_EQ s2, 2, 7
    CHECK_EQ s3, 2, 8

    // MIE is back on after MRET
    csrr    t0, mstatus
    andi    t0, t0, MSTATUS_MIE
    CHECK_EQ t0, MSTATUS_MIE, 9

    // Asynchronous interrupt while running
    li      s1, 0                       // don't check mepc
    IRQ_AFTER 25
    SPIN    100
    CHECK_EQ s2, 3, 10

    TEST_PASS

    .align 4
handler:
    addi    s2, s2, 1
    csrr    a0, mcause
    CHECK_EQ a0, MCAUSE_EXT_IRQ, 20
    csrr    a0, mtval
    CHECK_EQ a0, 0, 21
    csrr    a0, mstatus
    andi    a1, a0, MSTATUS_MIE
    CHECK_EQ a1, 0, 22
    andi    a1, a0, MSTATUS_MPIE
    CHECK_EQ a1, MSTATUS_MPIE, 23
    beqz    s1, 1f
    csrr    a0, mepc
    beq     a0, s1, 1f
    TEST_FAIL 24
1:  IRQ_CLEAR
    mret
