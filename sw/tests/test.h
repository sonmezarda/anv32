/*
 * Helpers for the core tests in sw/tests (run by tools/run_core_tests.py).
 *
 * tb_core_test.sv maps a small test device at TEST_BASE:
 *   +0x00 RESULT     write 1 = pass, any other value = fail code
 *   +0x04 IRQ_AFTER  write N: raise the external interrupt N cycles later
 *   +0x08 IRQ_CLEAR  write: lower the external interrupt
 *   +0x0C CYCLE      read: current cycle count
 *   +0x10 PUTC       write: print a character
 *
 * The macros use t5 and t6 as scratch registers. Tests must not keep live
 * values in them across a macro.
 */
#ifndef ANV32_TEST_H
#define ANV32_TEST_H

#define TEST_BASE       0x20000000
#define TEST_RESULT     0x00
#define TEST_IRQ_AFTER  0x04
#define TEST_IRQ_CLEAR  0x08
#define TEST_CYCLE      0x0C
#define TEST_PUTC       0x10

#define MSTATUS_MIE     0x00000008
#define MSTATUS_MPIE    0x00000080
#define MSTATUS_MPP_M   0x00001800
#define MIE_MSIE        0x00000008
#define MIE_MTIE        0x00000080
#define MIE_MEIE        0x00000800
#define MCAUSE_ILLEGAL  2
#define MCAUSE_ECALL_M  11
#define MCAUSE_EXT_IRQ  0x8000000B

.macro TEST_PASS
    li      t6, TEST_BASE
    li      t5, 1
    sw      t5, TEST_RESULT(t6)
99: j       99b
.endm

.macro TEST_FAIL code
    li      t6, TEST_BASE
    li      t5, \code
    sw      t5, TEST_RESULT(t6)
99: j       99b
.endm

/* Fail with \code unless \reg == \value. */
.macro CHECK_EQ reg, value, code
    li      t5, \value
    beq     \reg, t5, 98f
    TEST_FAIL \code
98:
.endm

.macro IRQ_AFTER cycles
    li      t6, TEST_BASE
    li      t5, \cycles
    sw      t5, TEST_IRQ_AFTER(t6)
.endm

.macro IRQ_AFTER_REG reg
    li      t6, TEST_BASE
    sw      \reg, TEST_IRQ_AFTER(t6)
.endm

.macro IRQ_CLEAR
    li      t6, TEST_BASE
    sw      zero, TEST_IRQ_CLEAR(t6)
.endm

#endif
