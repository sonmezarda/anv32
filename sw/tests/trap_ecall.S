// ECALL trap entry/exit: mcause, mepc, mtval and the mstatus MIE/MPIE/MPP
// stack. The second ECALL directly follows a write that sets MIE, so it also
// checks that the in-flight mstatus write does not overwrite trap entry.
#include "test.h"

    .section .text.init
    .globl _start
_start:
    la      t0, handler
    csrw    mtvec, t0
    csrw    mie, zero

    // MPP is hardwired to M
    csrr    t0, mstatus
    li      t1, MSTATUS_MPP_M
    and     t0, t0, t1
    CHECK_EQ t0, MSTATUS_MPP_M, 2

    // Case 1: ECALL with MIE = 0
    li      s0, 1
    la      s1, ecall_1
ecall_1:
    ecall
    CHECK_EQ s2, 1, 3                   // handler ran once
    csrr    t0, mstatus
    andi    t0, t0, MSTATUS_MIE
    CHECK_EQ t0, 0, 4                   // MIE restored to 0

    // Case 2: ECALL right after setting MIE
    li      s0, 2
    la      s1, ecall_2
    csrsi   mstatus, MSTATUS_MIE
ecall_2:
    ecall
    CHECK_EQ s2, 2, 5
    csrr    t0, mstatus
    andi    t0, t0, MSTATUS_MIE
    CHECK_EQ t0, MSTATUS_MIE, 6         // MIE restored to 1

    TEST_PASS

    .align 4
handler:
    addi    s2, s2, 1
    csrr    t0, mcause
    CHECK_EQ t0, MCAUSE_ECALL_M, 10
    csrr    t0, mepc
    bne     t0, s1, bad_mepc
    csrr    t0, mtval
    CHECK_EQ t0, 0, 12

    // Inside the handler MIE is always 0 and MPIE holds the old MIE.
    csrr    t0, mstatus
    andi    t1, t0, MSTATUS_MIE
    CHECK_EQ t1, 0, 13
    andi    t1, t0, MSTATUS_MPIE
    li      t2, 1
    beq     s0, t2, 1f
    CHECK_EQ t1, MSTATUS_MPIE, 14       // case 2: MIE was 1
    j       2f
1:  CHECK_EQ t1, 0, 15                  // case 1: MIE was 0
2:  csrr    t0, mepc
    addi    t0, t0, 4
    csrw    mepc, t0
    mret

bad_mepc:
    TEST_FAIL 11
