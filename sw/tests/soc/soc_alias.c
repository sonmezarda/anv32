/*
 * SET/CLR/XOR register aliases on the SYSCTRL LED and UART BAUD registers.
 * LED values keep the low nibble clear so the testbench does not read them
 * as a pass or fail code.
 */
#include <stdint.h>

#include "anv32_sysctrl.h"
#include "anv32_uart.h"
#include "soc_test.h"

#define LED_ADDR    (ANV32_SYSCTRL_BASE + ANV32_SYSCTRL_LED_OFFSET)

int main(void)
{
    ANV32_SYSCTRL_LED = 0x00F00000u;
    anv32_reg_set(&ANV32_SYSCTRL_LED, 0x00000300u);
    CHECK(ANV32_SYSCTRL_LED == 0x00F00300u, 2);
    anv32_reg_clr(&ANV32_SYSCTRL_LED, 0x00300000u);
    CHECK(ANV32_SYSCTRL_LED == 0x00C00300u, 3);
    anv32_reg_xor(&ANV32_SYSCTRL_LED, 0x00FF0000u);
    CHECK(ANV32_SYSCTRL_LED == 0x003F0300u, 4);

    /* Every alias reads the plain register value */
    CHECK(ANV32_REG32(LED_ADDR + ANV32_ALIAS_XOR_OFFSET) == 0x003F0300u, 5);
    CHECK(ANV32_REG32(LED_ADDR + ANV32_ALIAS_SET_OFFSET) == 0x003F0300u, 6);
    CHECK(ANV32_REG32(LED_ADDR + ANV32_ALIAS_CLR_OFFSET) == 0x003F0300u, 7);

    /* Byte stores only touch their own byte */
    ANV32_REG8(LED_ADDR + ANV32_ALIAS_SET_OFFSET + 1u) = 0x40u;
    CHECK(ANV32_SYSCTRL_LED == 0x003F4300u, 8);
    ANV32_REG8(LED_ADDR + ANV32_ALIAS_CLR_OFFSET + 2u) = 0x0Fu;
    CHECK(ANV32_SYSCTRL_LED == 0x00304300u, 9);
    ANV32_REG16(LED_ADDR + ANV32_ALIAS_XOR_OFFSET + 2u) = 0x1100u;
    CHECK(ANV32_SYSCTRL_LED == 0x11304300u, 10);

    /* Unimplemented registers in the slot read zero, through aliases too */
    ANV32_REG32(ANV32_SYSCTRL_BASE + 0x800u + 0x10u) = 0xFFFFFFFFu;
    CHECK(ANV32_REG32(ANV32_SYSCTRL_BASE + 0x10u) == 0u, 11);

    /* Same mechanism in another slot */
    ANV32_UART0_BAUD = 0x0001C200u;
    anv32_reg_clr(&ANV32_UART0_BAUD, 0x00000200u);
    anv32_reg_set(&ANV32_UART0_BAUD, 0x00030000u);
    CHECK(ANV32_UART0_BAUD == 0x0003C000u, 12);

    test_pass();
    return 0;
}
