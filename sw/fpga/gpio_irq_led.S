    .section .text.init
    .globl _start
    .type _start, @function

#define LED_BASE          0x10000
#define GPIO_IRQ_PENDING  0x10

_start:
    lui   s1, LED_BASE       # LED MMIO base: 0x1000_0000
    addi  s2, s1, GPIO_IRQ_PENDING
    addi  s0, zero, 0        # LED counter, updated only by irq handler

    sw    s0, 0(s1)
    addi  t0, zero, 1
    sw    t0, 0(s2)          # clear any stale pending GPIO interrupt

    lui   t0, %hi(trap_handler)
    addi  t0, t0, %lo(trap_handler)
    csrw  mtvec, t0

    # Enable machine external interrupt: mie.MEIE = bit 11.
    addi  t0, zero, 1
    slli  t0, t0, 11
    csrw  mie, t0

    # Enable global machine interrupts: mstatus.MIE = bit 3.
    addi  t0, zero, 8
    csrs  mstatus, t0

idle:
    jal   zero, idle

trap_handler:
    csrr  t0, mcause
    lui   t1, 0x80000
    addi  t1, t1, 11         # 0x8000_000b = machine external interrupt
    bne   t0, t1, fail_unknown

    addi  t0, zero, 1
    sw    t0, 0(s2)          # clear GPIO pending latch in the SoC

    addi  s0, s0, 1
    sw    s0, 0(s1)
    mret

fail_unknown:
    addi  t0, zero, 0x0e
    sw    t0, 0(s1)
    jal   zero, fail_unknown
