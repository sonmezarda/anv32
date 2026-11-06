// Load results used 1 to 3 instructions after the load, as every kind of
// operand, and operands that have to survive a stall after they were
// forwarded.
//
// On anv32im2 a consumer leaves D while the load is in M and picks the load
// result up in E1 when the load reaches W. If an older instruction then holds
// E2 (a divide, or a multiply with MUL_PIPE=1), the consumer sits in E1 while
// the load retires and has to keep the forwarded value. The same applies to a
// CSR read in E1 behind a CSR write that retires during the stall.
#include "test.h"

    .section .text.init
    .globl _start
_start:
    la      s0, data
    li      s1, 0                       // count of correct-path blocks

    // Distance 1, 2 and 3, as rs1 and as rs2
    lw      t0, 0(s0)
    addi    t1, t0, 1
    CHECK_EQ t1, 0x12345679, 2
    lw      t0, 0(s0)
    nop
    addi    t1, t0, 2
    CHECK_EQ t1, 0x1234567A, 3
    lw      t0, 0(s0)
    nop
    nop
    addi    t1, t0, 3
    CHECK_EQ t1, 0x1234567B, 4
    li      t2, 0x10
    lw      t0, 4(s0)
    sub     t1, t2, t0
    CHECK_EQ t1, 0x0000000E, 5
    lw      t0, 4(s0)
    nop
    sub     t1, t2, t0
    CHECK_EQ t1, 0x0000000E, 6

    // Both operands from two different loads
    lw      t0, 0(s0)
    lw      t1, 4(s0)
    add     t2, t0, t1
    CHECK_EQ t2, 0x1234567A, 7

    // Load result as an address (load-to-load), as store data and as a
    // store address
    lw      t0, 8(s0)                   // = address of data2
    lw      t1, 0(t0)
    CHECK_EQ t1, 0xCAFEF00D, 8
    lw      t0, 0(s0)
    sw      t0, 12(s0)
    lw      t1, 12(s0)
    CHECK_EQ t1, 0x12345678, 9
    lw      t0, 8(s0)
    sw      s0, 4(t0)                   // data2 + 4
    lw      t1, 4(t0)
    bne     t1, s0, fail_10

    // Load result in a branch and as a jalr target
    lw      t0, 0(s0)
    li      t2, 0x12345678
    beq     t0, t2, 1f
    TEST_FAIL 11
1:  addi    s1, s1, 1
    la      t2, 1f
    sw      t2, 12(s0)
    lw      t0, 12(s0)
    jalr    zero, 0(t0)
    TEST_FAIL 12
1:  addi    s1, s1, 1

    // A later write to the same register must win over the load
    lw      t0, 0(s0)
    li      t0, 5
    addi    t1, t0, 1
    CHECK_EQ t1, 6, 13

    // The consumer reaches E1 behind a divide that holds E2 while the load
    // retires; it must keep the forwarded load result for the whole stall
    li      a0, 100
    li      a1, 7
    lw      t0, 0(s0)
    div     a2, a0, a1
    addi    t1, t0, 1
    CHECK_EQ t1, 0x12345679, 14
    CHECK_EQ a2, 14, 15
    lw      t0, 4(s0)
    div     a2, a0, a1
    add     t1, t0, a2                  // also uses the divide result
    CHECK_EQ t1, 16, 16

    // Same with a multiply in between (holds E2 for one cycle with MUL_PIPE)
    lw      t0, 0(s0)
    mul     a2, a0, a1
    addi    t1, t0, 1
    CHECK_EQ t1, 0x12345679, 17
    lw      t0, 4(s0)
    mul     a2, a0, a1
    add     t1, t0, a2
    CHECK_EQ t1, 702, 18
    lw      t0, 4(s0)
    mul     a2, t0, a1                  // multiply on the load result
    mul     a3, a2, a1                  // and on the previous product
    CHECK_EQ a3, 98, 19

    // Divide on a load result, followed by a consumer of the quotient
    lw      t0, 0(s0)
    divu    a2, t0, a1
    addi    a3, a2, 0
    CHECK_EQ a3, 0x0299C335, 20

    // A CSR read in E1 behind a divide, with a CSR write ahead of the
    // divide that retires during the stall
    li      a3, 0x5A5A
    csrw    mscratch, a3
    div     a2, a0, a1
    csrr    t0, mscratch
    CHECK_EQ t0, 0x5A5A, 21

    CHECK_EQ s1, 2, 22
    TEST_PASS

fail_10:
    TEST_FAIL 10

    .align 2
data:
    .word   0x12345678
    .word   0x00000002
    .word   data2
    .word   0
data2:
    .word   0xCAFEF00D
    .word   0
