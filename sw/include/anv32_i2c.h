#ifndef ANV32_I2C_H
#define ANV32_I2C_H

#include "anv32_mmio.h"

#define ANV32_I2C_CMD_OFFSET            0x000u
#define ANV32_I2C_STATUS_OFFSET         0x004u
#define ANV32_I2C_RXDATA_OFFSET         0x008u
#define ANV32_I2C_CTRL_OFFSET           0x00Cu
/* Not implemented yet: timing is still set by i2c_periph parameters. */
#define ANV32_I2C_SCL_LOW_OFFSET        0x010u
#define ANV32_I2C_SCL_HIGH_OFFSET       0x014u
#define ANV32_I2C_TIMEOUT_OFFSET        0x018u

#define ANV32_I2C_CMD_WRITE             0u
#define ANV32_I2C_CMD_READ              1u
#define ANV32_I2C_CMD_RECOVER           2u
#define ANV32_I2C_CMD_START             (1u << 3)
#define ANV32_I2C_CMD_STOP              (1u << 4)
#define ANV32_I2C_CMD_ACK               (1u << 5)
#define ANV32_I2C_CMD_DATA(x)           (((x) & 0xffu) << 8)

#define ANV32_I2C_CTRL_CLEAR            (1u << 0)
#define ANV32_I2C_CTRL_IRQ_EN           (1u << 1)

#define ANV32_I2C_STATUS_BUSY           (1u << 0)
#define ANV32_I2C_STATUS_CMD_READY      (1u << 1)
#define ANV32_I2C_STATUS_RX_VALID       (1u << 2)
#define ANV32_I2C_STATUS_DONE           (1u << 3)
#define ANV32_I2C_STATUS_BUS_OWNED      (1u << 4)
#define ANV32_I2C_STATUS_BUS_FREE       (1u << 5)
#define ANV32_I2C_STATUS_SDA            (1u << 6)
#define ANV32_I2C_STATUS_SCL            (1u << 7)
#define ANV32_I2C_STATUS_NACK           (1u << 16)
#define ANV32_I2C_STATUS_ARB_LOST       (1u << 17)
#define ANV32_I2C_STATUS_TIMEOUT        (1u << 18)
#define ANV32_I2C_STATUS_BUS_BUSY       (1u << 19)
#define ANV32_I2C_STATUS_RX_OVF         (1u << 20)
#define ANV32_I2C_STATUS_CMD_OVF        (1u << 21)
#define ANV32_I2C_STATUS_ILLEGAL        (1u << 22)
#define ANV32_I2C_STATUS_REC_FAIL       (1u << 23)
#define ANV32_I2C_STATUS_ERROR          (ANV32_I2C_STATUS_NACK | \
                                         ANV32_I2C_STATUS_ARB_LOST | \
                                         ANV32_I2C_STATUS_TIMEOUT | \
                                         ANV32_I2C_STATUS_BUS_BUSY | \
                                         ANV32_I2C_STATUS_RX_OVF | \
                                         ANV32_I2C_STATUS_CMD_OVF | \
                                         ANV32_I2C_STATUS_ILLEGAL | \
                                         ANV32_I2C_STATUS_REC_FAIL)
/* Not a hardware bit: returned by software helpers when polling times out. */
#define ANV32_I2C_STATUS_SW_TIMEOUT     (1u << 31)

#define ANV32_I2C_CMD(base)             ANV32_REG32((base) + ANV32_I2C_CMD_OFFSET)
#define ANV32_I2C_STATUS(base)          ANV32_REG32((base) + ANV32_I2C_STATUS_OFFSET)
#define ANV32_I2C_RXDATA(base)          ANV32_REG32((base) + ANV32_I2C_RXDATA_OFFSET)
#define ANV32_I2C_CTRL(base)            ANV32_REG32((base) + ANV32_I2C_CTRL_OFFSET)
#define ANV32_I2C_SCL_LOW(base)         ANV32_REG32((base) + ANV32_I2C_SCL_LOW_OFFSET)
#define ANV32_I2C_SCL_HIGH(base)        ANV32_REG32((base) + ANV32_I2C_SCL_HIGH_OFFSET)
#define ANV32_I2C_TIMEOUT(base)         ANV32_REG32((base) + ANV32_I2C_TIMEOUT_OFFSET)

#define ANV32_I2C0_CMD                  ANV32_I2C_CMD(ANV32_I2C0_BASE)
#define ANV32_I2C0_STATUS               ANV32_I2C_STATUS(ANV32_I2C0_BASE)
#define ANV32_I2C0_RXDATA               ANV32_I2C_RXDATA(ANV32_I2C0_BASE)
#define ANV32_I2C0_CTRL                 ANV32_I2C_CTRL(ANV32_I2C0_BASE)
#define ANV32_I2C0_SCL_LOW              ANV32_I2C_SCL_LOW(ANV32_I2C0_BASE)
#define ANV32_I2C0_SCL_HIGH             ANV32_I2C_SCL_HIGH(ANV32_I2C0_BASE)
#define ANV32_I2C0_TIMEOUT              ANV32_I2C_TIMEOUT(ANV32_I2C0_BASE)

#endif
