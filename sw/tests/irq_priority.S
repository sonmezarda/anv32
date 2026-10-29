// Machine external, software and timer interrupts pending together are taken
// in the privileged-spec order MEI > MSI > MTI, each with its own mcause, and
// mie masks each source on its own.
#include "test.h"

#define CLINT_BASE      0x02000000
#define CLINT_MTIMECMP  (CLINT_BASE + 0x4000)
#define MCAUSE_SW       0x80000003
#define MCAUSE_TIMER    0x80000007
#define MIP_ALL         0x888                   // MEIP | MTIP | MSIP

// s0 = msip, s1 = mtimecmp, s5 = timeout, s6 = recorded causes, s7 = count.
// The handler only uses a2-a4 (and t5/t6 inside IRQ_CLEAR).

    .section .text.init
    .globl _start
_start:
    la      t0, handler
    csrw    mtvec, t0
    li      s0, CLINT_BASE
    li      s1, CLINT_MTIMECMP
    la      s6, causes
    li      s7, 0

    // Raise all three while interrupts are off
    li      t0, 1
    sw      t0, 0(s0)                   // msip
    sw      zero, 4(s1)                 // mtimecmp = 0
    sw      zero, 0(s1)
    IRQ_AFTER 1                         // external
    li      s5, 200
2:  csrr    t0, mip
    li      t1, MIP_ALL
    and     t0, t0, t1
    beq     t0, t1, 1f
    addi    s5, s5, -1
    bnez    s5, 2b
    TEST_FAIL 2
1:
    // Enable all three: the handler clears each source in turn
    li      t0, MIE_MSIE | MIE_MTIE | MIE_MEIE
    csrw    mie, t0
    csrsi   mstatus, MSTATUS_MIE
    li      s5, 2000
2:  li      t0, 3
    bgeu    s7, t0, 1f
    addi    s5, s5, -1
    bnez    s5, 2b
    TEST_FAIL 3
1:  csrci   mstatus, MSTATUS_MIE
    lw      t0, 0(s6)
    CHECK_EQ t0, MCAUSE_EXT_IRQ, 4
    lw      t0, 4(s6)
    CHECK_EQ t0, MCAUSE_SW, 5
    lw      t0, 8(s6)
    CHECK_EQ t0, MCAUSE_TIMER, 6
    CHECK_EQ s7, 3, 7

    // MSIP pending but masked by mie: only the timer is taken
    li      t0, 1
    sw      t0, 0(s0)
    sw      zero, 4(s1)
    sw      zero, 0(s1)
    li      t0, MIE_MTIE
    csrw    mie, t0
    csrsi   mstatus, MSTATUS_MIE
    li      s5, 2000
2:  li      t0, 4
    bgeu    s7, t0, 1f
    addi    s5, s5, -1
    bnez    s5, 2b
    TEST_FAIL 8
1:  csrci   mstatus, MSTATUS_MIE
    lw      t0, 12(s6)
    CHECK_EQ t0, MCAUSE_TIMER, 9
    CHECK_EQ s7, 4, 10
    csrr    t0, mip
    andi    t0, t0, 0x8
    CHECK_EQ t0, 0x8, 11                // MSIP still pending, never taken
    sw      zero, 0(s0)

    TEST_PASS

handler:
    csrr    a2, mcause
    slli    a3, s7, 2
    add     a3, a3, s6
    sw      a2, 0(a3)                   // record the cause
    addi    s7, s7, 1

    li      a3, MCAUSE_EXT_IRQ
    bne     a2, a3, 1f
    IRQ_CLEAR
    mret
1:  li      a3, MCAUSE_SW
    bne     a2, a3, 1f
    sw      zero, 0(s0)                 // msip = 0
    mret
1:  li      a3, MCAUSE_TIMER
    bne     a2, a3, 1f
    li      a4, -1
    sw      a4, 0(s1)                   // mtimecmp = all ones
    sw      a4, 4(s1)
    mret
1:  TEST_FAIL 12

    .align 2
causes:
    .word   0, 0, 0, 0, 0, 0, 0, 0
