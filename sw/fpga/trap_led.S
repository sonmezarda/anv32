    .section .text.init
    .globl _start
    .type _start, @function

#define LED_BASE    0x10000

_start:
    lui   s1, LED_BASE       # LED MMIO base: 0x1000_0000
    addi  s0, zero, 0        # trap flags: bit0=ecall, bit1=illegal

    lui   t0, %hi(trap_handler)
    addi  t0, t0, %lo(trap_handler)
    csrw  mtvec, t0

    ecall
    addi  t0, zero, 1
    bne   s0, t0, fail_ecall

illegal_site:
    .word 0xffffffff

    addi  t0, zero, 3
    bne   s0, t0, fail_illegal

pass_loop:
    addi  t0, zero, 0x0a
    sw    t0, 0(s1)
    jal   ra, delay
    addi  t0, zero, 0x05
    sw    t0, 0(s1)
    jal   ra, delay
    jal   zero, pass_loop

fail_ecall:
    addi  t0, zero, 0x01
    jal   zero, fail_loop

fail_illegal:
    addi  t0, zero, 0x02
    jal   zero, fail_loop

fail_unknown:
    addi  t0, zero, 0x0e

fail_loop:
    sw    t0, 0(s1)
    jal   zero, fail_loop

trap_handler:
    csrr  t0, mcause

    addi  t1, zero, 11
    beq   t0, t1, handle_ecall

    addi  t1, zero, 2
    beq   t0, t1, handle_illegal

    jal   zero, fail_unknown

handle_ecall:
    ori   s0, s0, 1
    jal   zero, trap_resume

handle_illegal:
    ori   s0, s0, 2

trap_resume:
    csrr  t2, mepc
    addi  t2, t2, 4
    csrw  mepc, t2
    mret

delay:
    lui   t2, 0x800
1:
    addi  t2, t2, -1
    bne   t2, zero, 1b
    jalr  zero, 0(ra)
