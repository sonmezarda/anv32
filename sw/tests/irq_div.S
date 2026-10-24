// Interrupts landing while the multi-cycle divider is busy. The divide is
// killed and restarted after the handler, so its result must still be right.
// The IRQ delay is swept across the whole divide latency.
//
// The handler only uses a0-a2, s7 and the macro scratch registers.
#include "test.h"

#define DELAYS  80
#define ITERS   3

    .section .text.init
    .globl _start
_start:
    la      t0, handler
    csrw    mtvec, t0
    li      t0, MIE_MEIE
    csrw    mie, t0
    csrsi   mstatus, MSTATUS_MIE

    li      s0, 1000003
    li      s1, 7
    li      s5, 0
    li      s6, DELAYS

sweep:
    IRQ_AFTER_REG s5
    li      s3, 0
    li      s4, ITERS
loop:
    div     t1, s0, s1                  // 142857
    rem     t2, s0, s1                  // 4
    mul     t3, t1, s1                  // 999999
    add     t3, t3, t2                  // 1000003
    sub     t3, t3, s0                  // 0
    add     s2, s2, t1
    add     s2, s2, t2
    or      s8, s8, t3                  // stays 0 unless something went wrong
    addi    s3, s3, 1
    blt     s3, s4, loop

    addi    t4, s5, 1
1:  bne     s7, t4, 1b
    addi    s5, s5, 1
    blt     s5, s6, sweep
sweep_end:

    CHECK_EQ s7, DELAYS, 2
    CHECK_EQ s8, 0, 3
    CHECK_EQ s2, DELAYS * ITERS * (142857 + 4), 4
    TEST_PASS

    .align 4
handler:
    addi    s7, s7, 1
    csrr    a0, mepc
    la      a1, sweep
    la      a2, sweep_end
    bltu    a0, a1, bad_mepc
    bgeu    a0, a2, bad_mepc
    IRQ_CLEAR
    mret
bad_mepc:
    TEST_FAIL 20
