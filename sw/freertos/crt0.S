    # Startup for FreeRTOS programs (sw/freertos/link.ld). Unlike
    # sw/common/crt0.S it clears .bss: the kernel relies on its zero-initialised
    # globals, and the BRAM image does not cover .bss.
    .section .text.init
    .globl _start
    .type _start, @function

_start:
    # Until main() installs the FreeRTOS trap handler, any trap stops in _halt.
    la    t0, _halt
    csrw  mtvec, t0
    la    sp, _stack_top

    la    t0, _bss_start
    la    t1, _bss_end
1:
    bgeu  t0, t1, 2f
    sw    zero, 0(t0)
    addi  t0, t0, 4
    j     1b
2:
    call  main
    ebreak

    .align 2
_halt:
    j     _halt
