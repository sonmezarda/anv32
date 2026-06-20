    .section .text.init
    .globl _start
    .type _start, @function

_start:
    lui   t0, 0x10000        # LED MMIO base: 0x1000_0000
    addi  t1, zero, 0        

1:
    addi  t1, t1, 1
    sw    t1, 0(t0)

    lui   t2, 0x80           # crude visible delay
2:
    addi  t2, t2, -1
    bne   t2, zero, 2b
    jal   zero, 1b
