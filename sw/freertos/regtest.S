    # Register test tasks, after the RegTest tasks of the FreeRTOS demos. Each
    # task fills every register the port saves (x1, x5-x31) with its own
    # pattern, then checks them in a loop and bumps a counter. Two of them run
    # at the same priority, so the tick interrupt keeps switching between them
    # at arbitrary points; a register the context switch loses or swaps shows
    # up as a mismatch. x31 is the scratch register for the checks.

    .macro fill base
    li    x1,  \base + 1
    li    x5,  \base + 5
    li    x6,  \base + 6
    li    x7,  \base + 7
    li    x8,  \base + 8
    li    x9,  \base + 9
    li    x10, \base + 10
    li    x11, \base + 11
    li    x12, \base + 12
    li    x13, \base + 13
    li    x14, \base + 14
    li    x15, \base + 15
    li    x16, \base + 16
    li    x17, \base + 17
    li    x18, \base + 18
    li    x19, \base + 19
    li    x20, \base + 20
    li    x21, \base + 21
    li    x22, \base + 22
    li    x23, \base + 23
    li    x24, \base + 24
    li    x25, \base + 25
    li    x26, \base + 26
    li    x27, \base + 27
    li    x28, \base + 28
    li    x29, \base + 29
    li    x30, \base + 30
    .endm

    .macro check reg, value
    li    x31, \value
    bne   \reg, x31, vRegTestError
    .endm

    .macro check_all base
    check x1,  \base + 1
    check x5,  \base + 5
    check x6,  \base + 6
    check x7,  \base + 7
    check x8,  \base + 8
    check x9,  \base + 9
    check x10, \base + 10
    check x11, \base + 11
    check x12, \base + 12
    check x13, \base + 13
    check x14, \base + 14
    check x15, \base + 15
    check x16, \base + 16
    check x17, \base + 17
    check x18, \base + 18
    check x19, \base + 19
    check x20, \base + 20
    check x21, \base + 21
    check x22, \base + 22
    check x23, \base + 23
    check x24, \base + 24
    check x25, \base + 25
    check x26, \base + 26
    check x27, \base + 27
    check x28, \base + 28
    check x29, \base + 29
    check x30, \base + 30
    .endm

    # x30 doubles as the counter scratch, then gets its pattern back.
    .macro regtest name, base, counter
    .section .text.\name
    .globl \name
    .type \name, @function
\name:
    fill \base
1:
    check_all \base
    la    x31, \counter
    lw    x30, 0(x31)
    addi  x30, x30, 1
    sw    x30, 0(x31)
    li    x30, \base + 30
    li    x31, \base + 31
    j     1b
    .endm

    regtest vRegTest1Task, 0x11110000, ulRegTest1Counter
    regtest vRegTest2Task, 0x22220000, ulRegTest2Counter

    .section .text.vRegTestError
vRegTestError:
    j     vRegTestFailed

    .section .bss.regtest
    .globl ulRegTest1Counter
    .globl ulRegTest2Counter
    .align 2
ulRegTest1Counter:
    .word 0
ulRegTest2Counter:
    .word 0
