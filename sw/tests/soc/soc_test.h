/*
 * Helpers for the SoC tests in sw/tests/soc (run by tools/run_core_tests.py).
 *
 * tb_soc_test.sv watches the SYSCTRL LED register:
 *   0x2                  pass
 *   (code << 8) | 0xF    fail with code
 *   0x5                  request: pulse the GPIO interrupt input once
 * The UART TX pin is looped back to RX.
 */
#ifndef ANV32_SOC_TEST_H
#define ANV32_SOC_TEST_H

#include "anv32_sysctrl.h"

#define SOC_TEST_PASS          0x2u
#define SOC_TEST_GPIO_PULSE    0x5u

static inline void test_pass(void)
{
    ANV32_SYSCTRL_LED = SOC_TEST_PASS;
    for (;;) {
    }
}

static inline void test_fail(unsigned int code)
{
    ANV32_SYSCTRL_LED = (code << 8) | 0xFu;
    for (;;) {
    }
}

#define CHECK(cond, code)       \
    do {                        \
        if (!(cond)) {          \
            test_fail(code);    \
        }                       \
    } while (0)

#endif
