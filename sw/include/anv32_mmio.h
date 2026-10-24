#ifndef ANV32_MMIO_H
#define ANV32_MMIO_H

#include <stdint.h>

/*
 * ANV32 memory map: global regions, peripheral base addresses and MMIO
 * helpers. Register layouts live in the per-peripheral headers.
 */

#define ANV32_BRAM_BASE             0x00000000u
#define ANV32_BRAM_SIZE             0x00010000u  /* region size; 4 KiB populated today */

/* Reserved, no hardware yet */
#define ANV32_BOOTROM_BASE          0x00010000u
#define ANV32_BOOTROM_SIZE          0x00010000u

#define ANV32_MMIO_BASE             0x10000000u
#define ANV32_MMIO_SIZE             0x00010000u
#define ANV32_MMIO_SLOT_SIZE        0x00001000u

#define ANV32_SYSCTRL_BASE          0x10000000u
#define ANV32_GPIO0_BASE            0x10001000u
#define ANV32_UART0_BASE            0x10002000u
#define ANV32_I2C0_BASE             0x10003000u
/* Reserved slots, no hardware yet */
#define ANV32_SPI0_BASE             0x10004000u
#define ANV32_TIMER0_BASE           0x10005000u
#define ANV32_PWM0_BASE             0x10006000u
#define ANV32_IRQCTRL_BASE          0x10007000u
#define ANV32_WATCHDOG_BASE         0x10008000u
#define ANV32_UART1_BASE            0x10009000u

#define ANV32_NN_BASE               0x10010000u
#define ANV32_NN_SIZE               0x00010000u
#define ANV32_NN_SCRATCH_BASE       0x10011000u

/* Reserved, no hardware yet */
#define ANV32_DMA_BASE              0x10020000u
#define ANV32_DMA_SIZE              0x00010000u

/* External devices and memory, no hardware yet */
#define ANV32_EXT_DEVICE_BASE       0x20000000u
#define ANV32_EXT_DEVICE_SIZE       0x10000000u

#define ANV32_EXT_RAM_BASE          0x80000000u
#define ANV32_EXT_RAM_SIZE          0x10000000u

#define ANV32_REG32(addr)           (*(volatile uint32_t *)(uintptr_t)(addr))
#define ANV32_REG16(addr)           (*(volatile uint16_t *)(uintptr_t)(addr))
#define ANV32_REG8(addr)            (*(volatile uint8_t *)(uintptr_t)(addr))

#endif
