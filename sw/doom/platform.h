/*
 * Simulation platform device (sim/tb/common/tb_platform.sv).
 */
#ifndef DOOM_PLATFORM_H
#define DOOM_PLATFORM_H

#include <stdint.h>

#define PLATFORM_DEV_BASE       0x20000000u
#define PLATFORM_REG(offset)    (*(volatile uint32_t *)(uintptr_t)(PLATFORM_DEV_BASE + (offset)))

#define PLATFORM_EXIT           PLATFORM_REG(0x00u)
#define PLATFORM_PUTC           PLATFORM_REG(0x10u)
#define PLATFORM_PALETTE        PLATFORM_REG(0x20u)
#define PLATFORM_FRAME          PLATFORM_REG(0x24u)

/* Clock the tick count assumes. Only affects game time, not correctness. */
#ifndef PLATFORM_CPU_HZ
#define PLATFORM_CPU_HZ         50000000u
#endif

#endif
