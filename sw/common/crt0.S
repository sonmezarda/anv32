    .section .text.init
    .globl _start
    .type _start, @function

_start:
    # Until main() installs its own handler, any trap stops in _halt.
    la    t0, _halt
    csrw  mtvec, t0
    la    sp, _stack_top
    call  main
    la    t0, _test_result
    sw    a0, 0(t0)
    # Simulation testbenches stop at this EBREAK; on hardware it traps to _halt.
    ebreak

    .align 2
_halt:
    j     _halt

    .section .bss
    .globl _test_result
    .align 2
_test_result:
    .word 0
