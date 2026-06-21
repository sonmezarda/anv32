    .section .text.init
    .globl _start
    .type _start, @function

_start:
    addi  x31, zero, 0

    lui   x5, %hi(trap_handler)
    addi  x5, x5, %lo(trap_handler)
    csrw  mtvec, x5

ecall_site:
    ecall

after_ecall:
    addi  x31, zero, 0x7d
    ebreak

trap_handler:
    csrr  x6, mcause
    addi  x7, zero, 11
    bne   x6, x7, fail_mcause

    csrr  x28, mepc
    lui   x29, %hi(ecall_site)
    addi  x29, x29, %lo(ecall_site)
    bne   x28, x29, fail_mepc

    addi  x28, x28, 4
    csrw  mepc, x28
    mret

fail_mcause:
    addi  x31, zero, 1
    ebreak

fail_mepc:
    addi  x31, zero, 2
    ebreak
