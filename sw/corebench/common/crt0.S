// corebench startup: any core, RAM at address 0. Clears .bss, runs main()
// and reports its return value as the exit code. A trap ends the run and
// reports mepc/mcause instead of looping through a missing handler.
#include "corebench.h"

    .section .text.init
    .globl _start
    .type _start, @function
_start:
    la    t0, _corebench_trap
    csrw  mtvec, t0
    la    sp, _stack_top

    la    t0, _bss_start
    la    t1, _bss_end
1:  bgeu  t0, t1, 2f
    sw    zero, 0(t0)
    addi  t0, t0, 4
    j     1b

2:  call  main
    li    t0, COREBENCH_CTRL_BASE
    sw    a0, COREBENCH_EXIT(t0)
3:  j     3b

    // 256-byte aligned so it also works as a vectored mtvec base
    .align 8
_corebench_trap:
    li    t0, COREBENCH_CTRL_BASE
    csrr  t1, mepc
    sw    t1, COREBENCH_TRAP_EPC(t0)
    csrr  t1, mcause
    sw    t1, COREBENCH_TRAP_CAUSE(t0)
4:  j     4b
