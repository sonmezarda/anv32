// Interrupt enable/disable windows. Each loop iteration opens a short window
// (one instruction between enable and disable) followed by a critical
// section. Over a sweep of IRQ delays, the interrupt must:
//   - only be taken inside the open window, never in the critical section
//   - actually be taken there (not starve until interrupts are enabled again)
//
// Phase 1 toggles mstatus.MIE with mie.MEIE = 1.
// Phase 2 toggles mie.MEIE with mstatus.MIE = 1.
//
// The handler accepts mepc in [s10, s11) and sets s9 when it runs.
#include "test.h"

#define DELAYS  48
#define ITERS   16

    .section .text.init
    .globl _start
_start:
    la      t0, handler
    csrw    mtvec, t0

// ---- Phase 1: mstatus.MIE --------------------------------------------------
    li      t0, MIE_MEIE
    csrw    mie, t0
    la      s10, p1_open
    la      s11, p1_crit
    li      s5, 0
    li      s6, DELAYS
p1_sweep:
    li      s9, 0
    IRQ_AFTER_REG s5
    li      s3, 0
    li      s4, ITERS
p1_loop:
    csrsi   mstatus, MSTATUS_MIE
p1_open:
    addi    s3, s3, 1
    csrci   mstatus, MSTATUS_MIE
p1_crit:
    addi    s2, s2, 1
    addi    s2, s2, 1
    addi    s2, s2, 1
    blt     s3, s4, p1_loop
    CHECK_EQ s9, 1, 2                   // taken inside the loop
    addi    s5, s5, 1
    blt     s5, s6, p1_sweep
    CHECK_EQ s7, DELAYS, 3
    CHECK_EQ s2, DELAYS * ITERS * 3, 4

// ---- Phase 2: mie.MEIE -----------------------------------------------------
    csrw    mie, zero
    csrsi   mstatus, MSTATUS_MIE
    li      t0, MIE_MEIE
    la      s10, p2_open
    la      s11, p2_crit
    li      s2, 0
    li      s7, 0
    li      s5, 0
p2_sweep:
    li      s9, 0
    IRQ_AFTER_REG s5
    li      s3, 0
p2_loop:
    csrs    mie, t0
p2_open:
    addi    s3, s3, 1
    csrc    mie, t0
p2_crit:
    addi    s2, s2, 1
    addi    s2, s2, 1
    addi    s2, s2, 1
    blt     s3, s4, p2_loop
    CHECK_EQ s9, 1, 5
    addi    s5, s5, 1
    blt     s5, s6, p2_sweep
    CHECK_EQ s7, DELAYS, 6
    CHECK_EQ s2, DELAYS * ITERS * 3, 7

    TEST_PASS

    .align 4
handler:
    addi    s7, s7, 1
    csrr    a0, mepc
    bltu    a0, s10, bad_mepc
    bgeu    a0, s11, bad_mepc
    li      s9, 1
    IRQ_CLEAR
    mret
bad_mepc:
    TEST_FAIL 20
