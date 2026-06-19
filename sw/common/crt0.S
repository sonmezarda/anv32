    .section .text.init
    .globl _start
    .type _start, @function

_start:
    la    sp, _stack_top
    call  main
    la    t0, _test_result
    sw    a0, 0(t0)
    ebreak

1:
    j     1b

    .section .bss
    .globl _test_result
    .align 2
_test_result:
    .word 0
