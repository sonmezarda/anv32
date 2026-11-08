// A divide that enters E (E2 on anv32im2) while the load or store ahead of it
// in M waits on mem_ready. The divide stalls E and sends bubbles to M, but the
// access already in M has to stay there until the bus accepts it. If it is
// dropped, a load leaves its register unchanged and a store never happens.
//
// Run with +mem_wait_fixed=<n> so every data access is guaranteed to stall
// (see the "mem_wait_fixed" field in tests.json).
#include "test.h"

    .section .text.init
    .globl _start
_start:
    la      s0, data
    li      a0, 8000
    li      a1, 1000

    // divu right behind a load
    li      t0, 0
    lw      t0, 0(s0)
    divu    a2, a0, a1
    CHECK_EQ t0, 0x11111111, 2
    CHECK_EQ a2, 8, 3

    // two loads, then a divu that uses neither
    li      t0, 0
    li      t1, 0
    lw      t0, 0(s0)
    lw      t1, 4(s0)
    divu    a2, a0, a1
    CHECK_EQ t0, 0x11111111, 4
    CHECK_EQ t1, 0x22222222, 5
    CHECK_EQ a2, 8, 6

    // the divisor comes from the first load, the second load sits in M
    li      t1, 0
    lw      a5, 8(s0)
    lw      t1, 4(s0)
    divu    a2, a0, a5
    CHECK_EQ t1, 0x22222222, 7
    CHECK_EQ a2, 8, 8

    // divu right behind a store
    li      t1, 0x33333333
    sw      t1, 12(s0)
    divu    a2, a0, a1
    lw      t2, 12(s0)
    CHECK_EQ t2, 0x33333333, 9
    CHECK_EQ a2, 8, 10

    // rem right behind a load, result used at once
    li      t1, 0
    li      a3, 8003
    lw      t1, 4(s0)
    remu    a2, a3, a1
    addi    a2, a2, 1
    CHECK_EQ t1, 0x22222222, 11
    CHECK_EQ a2, 4, 12

    // loop: each iteration loads, then divides behind the load
    li      t3, 5
    li      t4, 0
    li      s1, 0
1:  lw      t0, 8(s0)
    divu    a2, a0, a1
    add     t4, t4, t0
    add     s1, s1, a2
    addi    t3, t3, -1
    bnez    t3, 1b
    CHECK_EQ t4, 5000, 13
    CHECK_EQ s1, 40, 14

    TEST_PASS

    .align 2
data:
    .word   0x11111111
    .word   0x22222222
    .word   1000
    .word   0
