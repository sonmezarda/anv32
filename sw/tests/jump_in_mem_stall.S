// A taken jump or branch that sits in E (E1/E2 on anv32im2) while the load or
// store ahead of it in M waits on mem_ready. The stall freezes fetch, so the
// redirect must survive the stall and be taken when it ends. If a jump is
// dropped, execution falls through into the TEST_FAIL right behind it.
//
// Run with +mem_wait_fixed=<n> so every data access is guaranteed to stall
// (see the "mem_wait_fixed" field in tests.json).
#include "test.h"

    .section .text.init
    .globl _start
_start:
    la      s0, data
    li      s1, 0                       // count of correct-path blocks

    // jal right behind a load (E/E2 while the load waits in M)
    lw      t0, 0(s0)
    j       1f
    TEST_FAIL 2
1:  addi    s1, s1, 1

    // jal right behind a store
    sw      s1, 8(s0)
    j       1f
    TEST_FAIL 3
1:  addi    s1, s1, 1

    // jal one instruction further back (E1 on anv32im2)
    lw      t0, 0(s0)
    addi    t1, zero, 7
    j       1f
    TEST_FAIL 4
1:  addi    s1, s1, 1

    // taken beq / bne / bltu that do not depend on the load
    lw      t0, 0(s0)
    beq     zero, zero, 1f
    TEST_FAIL 5
1:  addi    s1, s1, 1
    li      t1, 1
    lw      t0, 0(s0)
    bne     t1, zero, 1f
    TEST_FAIL 6
1:  addi    s1, s1, 1
    li      t2, 2
    sw      t2, 8(s0)
    bltu    t1, t2, 1f
    TEST_FAIL 7
1:  addi    s1, s1, 1

    // branch on the loaded value: load-use stall and memory stall together
    li      t2, 0x12345678
    lw      t0, 0(s0)
    beq     t0, t2, 1f
    TEST_FAIL 8
1:  addi    s1, s1, 1

    // call and return: jal behind a load, then jalr (ret) behind a load
    lw      t0, 0(s0)
    jal     ra, func
    addi    s1, s1, 1                   // return lands here
    CHECK_EQ t3, 0x0000ABCD, 9

    // indirect jump behind a store
    la      t4, 1f
    sw      zero, 8(s0)
    jalr    zero, 0(t4)
    TEST_FAIL 10
1:  addi    s1, s1, 1

    // two loads, then a jump
    lw      t0, 0(s0)
    lw      t1, 4(s0)
    j       1f
    TEST_FAIL 11
1:  addi    s1, s1, 1

    // loop: each iteration ends in a load followed by the taken back edge
    li      t1, 10
    li      t2, 0
2:  addi    t2, t2, 1
    addi    t1, t1, -1
    lw      t0, 0(s0)
    bnez    t1, 2b
    CHECK_EQ t2, 10, 12

    CHECK_EQ s1, 10, 13
    TEST_PASS

func:
    lw      t3, 4(s0)
    ret
    TEST_FAIL 14

    .align 2
data:
    .word   0x12345678
    .word   0x0000ABCD
    .word   0
