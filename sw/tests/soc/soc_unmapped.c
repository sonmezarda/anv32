/*
 * Accesses to addresses with no hardware behind them (unimplemented
 * registers, reserved slots and regions) must ignore writes, read as zero and
 * leave RAM untouched.
 */
#include <stdint.h>

#include "anv32_gpio.h"
#include "anv32_i2c.h"
#include "anv32_mmio.h"
#include "soc_test.h"

static const uint32_t unmapped[] = {
    ANV32_GPIO0_BASE + ANV32_GPIO_DATA_OFFSET,
    ANV32_GPIO0_BASE + ANV32_GPIO_DIR_OFFSET,
    ANV32_SYSCTRL_BASE + ANV32_SYSCTRL_BOARD_ID_OFFSET,
    ANV32_I2C0_BASE + ANV32_I2C_SCL_LOW_OFFSET,
    ANV32_SPI0_BASE,
    ANV32_TIMER0_BASE + 0x10u,
    ANV32_DMA_BASE,
    ANV32_NN_SCRATCH_BASE + 0x4000u,    /* just past the NN scratch */
    ANV32_EXT_DEVICE_BASE,
    ANV32_EXT_RAM_BASE + 0x40u,
};

#define COUNT (sizeof(unmapped) / sizeof(unmapped[0]))

int main(void)
{
    uint32_t before[COUNT];
    unsigned int i;

    /* RAM words the addresses would alias onto if decode were incomplete */
    for (i = 0; i < COUNT; i++) {
        before[i] = ANV32_REG32(unmapped[i] & 0xFFCu);
    }

    for (i = 0; i < COUNT; i++) {
        ANV32_REG32(unmapped[i]) = 0xA5A5A5A5u;
        CHECK(ANV32_REG32(unmapped[i]) == 0u, 10 + i);
    }

    for (i = 0; i < COUNT; i++) {
        CHECK(ANV32_REG32(unmapped[i] & 0xFFCu) == before[i], 30 + i);
    }

    test_pass();
    return 0;
}
