// Interrupts at every point of a loop with a load-use pair and a taken jump.
// The IRQ delay is swept over DELAYS values. A dropped, duplicated or
// wrong-path instruction shows up as a bad checksum, a bad mepc or the
// TEST_FAIL after the jump being executed.
//
// The handler only uses a0-a2, s7 and the macro scratch registers. The
// interruptible code does not use any of them.
#include "test.h"

#define DELAYS  48
#define ITERS   12

    .section .text.init
    .globl _start
_start:
    la      t0, handler
    csrw    mtvec, t0
    li      t0, MIE_MEIE
    csrw    mie, t0
    csrsi   mstatus, MSTATUS_MIE

    la      s0, data                    // data word = 3
    li      s5, 0                       // current delay
    li      s6, DELAYS

sweep:
    IRQ_AFTER_REG s5
    li      s3, 0
    li      s4, ITERS
loop:
    lw      t1, 0(s0)
    addi    t2, t1, 1                   // load-use
    add     s2, s2, t2                  // checksum += 4
    addi    s3, s3, 1
    j       check
    TEST_FAIL 20                        // wrong path, must never run
check:
    blt     s3, s4, loop

    addi    t3, s5, 1                   // wait for this delay's interrupt
1:  bne     s7, t3, 1b
    addi    s5, s5, 1
    blt     s5, s6, sweep
sweep_end:

    CHECK_EQ s7, DELAYS, 2
    CHECK_EQ s2, DELAYS * ITERS * 4, 3
    TEST_PASS

    .align 4
handler:
    addi    s7, s7, 1
    csrr    a0, mcause
    CHECK_EQ a0, MCAUSE_EXT_IRQ, 21
    csrr    a0, mepc
    la      a1, sweep
    la      a2, sweep_end
    bltu    a0, a1, bad_mepc
    bgeu    a0, a2, bad_mepc
    IRQ_CLEAR
    mret
bad_mepc:
    TEST_FAIL 22

    .align 2
data:
    .word   3
