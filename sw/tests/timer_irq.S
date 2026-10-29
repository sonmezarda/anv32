// CLINT machine timer: reset state, mtime counting and writes, MTIP masked by
// mie.MTIE, then periodic timer interrupts where the handler moves mtimecmp
// forward. tb_core_test ticks mtime every 4 clocks.
#include "test.h"

#define CLINT_BASE      0x02000000
#define CLINT_MTIMECMP  (CLINT_BASE + 0x4000)
#define CLINT_MTIME     (CLINT_BASE + 0xBFF8)
#define MCAUSE_TIMER    0x80000007
#define MIP_MTIP        0x80
#define PERIOD          20              // mtime ticks between interrupts
#define TICKS           5

// s1 = mtimecmp, s2 = mtime, s3 = interrupts taken, s4 = mtime at the last
// one, s5 = timeout. The handler only uses a2-a5.

    .section .text.init
    .globl _start
_start:
    la      t0, handler
    csrw    mtvec, t0
    li      s1, CLINT_MTIMECMP
    li      s2, CLINT_MTIME
    li      s3, 0

    // Reset: mtimecmp is all ones, so the timer is not pending
    lw      t0, 0(s1)
    CHECK_EQ t0, 0xFFFFFFFF, 2
    lw      t0, 4(s1)
    CHECK_EQ t0, 0xFFFFFFFF, 3
    csrr    t0, mip
    andi    t0, t0, MIP_MTIP
    CHECK_EQ t0, 0, 4

    // mtime counts
    lw      a0, 0(s2)
    li      t0, 40
1:  addi    t0, t0, -1
    bnez    t0, 1b
    lw      a1, 0(s2)
    bgtu    a1, a0, 1f
    TEST_FAIL 5
1:
    // mtime is writable and keeps counting from the written value
    sw      zero, 4(s2)
    li      t0, 0x1000
    sw      t0, 0(s2)
    lw      t1, 0(s2)
    li      t2, 0x1000
    bgeu    t1, t2, 1f
    TEST_FAIL 6
1:  li      t2, 0x1010
    bltu    t1, t2, 1f
    TEST_FAIL 7
1:
    // mtimecmp <= mtime: MTIP is pending, but mie.MTIE = 0 keeps it masked
    sw      zero, 4(s1)
    sw      zero, 0(s1)
    li      s5, 100
2:  csrr    t0, mip
    andi    t0, t0, MIP_MTIP
    bnez    t0, 1f
    addi    s5, s5, -1
    bnez    s5, 2b
    TEST_FAIL 8
1:  CHECK_EQ s3, 0, 9

    // Unmask: the handler takes TICKS periodic interrupts
    li      t0, MIE_MTIE
    csrs    mie, t0
    csrsi   mstatus, MSTATUS_MIE
    li      s5, 20000
2:  li      t0, TICKS
    bgeu    s3, t0, 1f
    addi    s5, s5, -1
    bnez    s5, 2b
    TEST_FAIL 10
1:  csrci   mstatus, MSTATUS_MIE

    // Moving mtimecmp past mtime clears MTIP
    li      t0, -1
    sw      t0, 0(s1)
    sw      t0, 4(s1)
    li      s5, 100
2:  csrr    t0, mip
    andi    t0, t0, MIP_MTIP
    beqz    t0, 1f
    addi    s5, s5, -1
    bnez    s5, 2b
    TEST_FAIL 11
1:  TEST_PASS

handler:
    csrr    a2, mcause
    li      a3, MCAUSE_TIMER
    beq     a2, a3, 1f
    TEST_FAIL 12
1:  lw      a2, 0(s2)                   // mtime on entry
    beqz    s3, 2f
    // Every tick after the first comes at least PERIOD after the previous
    // one. A stale MTIP right after the mtimecmp store would re-enter at once.
    sub     a4, a2, s4
    li      a5, PERIOD
    bgeu    a4, a5, 2f
    TEST_FAIL 13
2:  mv      s4, a2
    addi    s3, s3, 1
    addi    a3, a2, PERIOD
    // The store that clears MTIP sits right before mret: the closest a
    // handler can get to re-enabling interrupts while MTIP is still stale.
    sw      a3, 0(s1)                   // mtimecmp high word is already 0
    mret
