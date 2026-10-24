// CSR instruction semantics and back-to-back forwarding of CSR values.
#include "test.h"

    .section .text.init
    .globl _start
_start:
    // Write then read immediately
    li      a0, 0x100
    csrw    mtvec, a0
    csrr    t0, mtvec
    CHECK_EQ t0, 0x100, 2

    // CSRRW returns the old value
    li      a1, 0x200
    csrrw   t1, mtvec, a1
    CHECK_EQ t1, 0x100, 3
    csrr    t0, mtvec
    CHECK_EQ t0, 0x200, 4

    // CSRRS / CSRRC
    li      a2, 0x0F0
    csrrs   t1, mtvec, a2
    CHECK_EQ t1, 0x200, 5
    li      a3, 0x200
    csrrc   t1, mtvec, a3
    CHECK_EQ t1, 0x2F0, 6
    csrr    t0, mtvec
    CHECK_EQ t0, 0x0F0, 7

    // Immediate forms
    csrrwi  zero, mscratch, 0x14
    csrrsi  t1, mscratch, 0x3
    CHECK_EQ t1, 0x14, 8
    csrrci  t1, mscratch, 0x4
    CHECK_EQ t1, 0x17, 9
    csrr    t0, mscratch
    CHECK_EQ t0, 0x13, 10

    // CSRRS/CSRRC with rs1 = x0 must not write
    li      a0, 0x55
    csrw    mtval, a0
    csrrs   t1, mtval, zero
    csrrc   t2, mtval, zero
    csrr    t0, mtval
    CHECK_EQ t0, 0x55, 11
    CHECK_EQ t2, 0x55, 12

    // CSR result used by the very next instruction
    csrr    t0, mtval
    addi    t1, t0, 1
    CHECK_EQ t1, 0x56, 13

    // Back-to-back writes to the same CSR
    li      a0, 1
    li      a1, 2
    li      a2, 3
    csrw    mcause, a0
    csrw    mcause, a1
    csrw    mcause, a2
    csrr    t0, mcause
    CHECK_EQ t0, 3, 14

    // WARL fields: only the legal bits stick, also when read back at once
    li      a0, -1
    csrw    mepc, a0
    csrr    t0, mepc
    CHECK_EQ t0, 0xFFFFFFFC, 16         // IALIGN = 32
    csrw    mtvec, a0
    csrr    t0, mtvec
    CHECK_EQ t0, 0xFFFFFFFC, 17         // direct mode only
    csrw    mie, a0
    csrr    t0, mie
    CHECK_EQ t0, MIE_MEIE, 18           // external interrupt only
    csrw    mstatus, a0
    csrr    t0, mstatus
    CHECK_EQ t0, MSTATUS_MPP_M | MSTATUS_MPIE | MSTATUS_MIE, 19
    csrw    mstatus, zero
    csrr    t0, mstatus
    CHECK_EQ t0, MSTATUS_MPP_M, 20

    // Read-only and constant CSRs
    csrr    t0, misa
    srli    t0, t0, 30
    CHECK_EQ t0, 1, 21                  // MXL = 32-bit
    csrr    t0, misa
    andi    t0, t0, 0x100
    CHECK_EQ t0, 0x100, 22              // I
    csrr    t0, mhartid
    CHECK_EQ t0, 0, 23
    csrw    misa, zero                  // legal, but has no effect
    csrr    t0, misa
    srli    t0, t0, 30
    CHECK_EQ t0, 1, 24

    // Counters run, and the instret alias matches minstret
    csrr    t1, mcycle
    nop
    csrr    t2, mcycle
    bltu    t1, t2, 1f
    TEST_FAIL 25
1:  csrw    minstret, zero
    nop
    nop
    csrr    t0, minstret
    CHECK_EQ t0, 2, 26                  // the two nops
    csrr    t0, instret
    CHECK_EQ t0, 5, 27                  // + csrr, and li/beq from CHECK_EQ

    // A trap right after writing mtvec must use the new value
    la      t0, handler
    csrw    mtvec, t0
    ecall
    CHECK_EQ s2, 1, 15

    TEST_PASS

    .align 4
handler:
    addi    s2, s2, 1
    csrr    t0, mepc
    addi    t0, t0, 4
    csrw    mepc, t0
    mret
