#ifndef ANV32_CLINT_H
#define ANV32_CLINT_H

#include "anv32_mmio.h"

/*
 * CLINT: the RISC-V machine timer and machine software interrupt, in the
 * SiFive CLINT / ACLINT register layout.
 *
 *   msip      bit 0 raises the machine software interrupt (mcause 0x80000003)
 *   mtimecmp  the machine timer interrupt (mcause 0x80000007) is pending
 *             while mtime >= mtimecmp; move mtimecmp forward to clear it
 *   mtime     64-bit, counts at ANV32_MTIME_FREQ, writable
 *
 * mtimecmp resets to all ones, so the timer never fires before software sets
 * it. Enable with mie.MTIE (bit 7) / mie.MSIE (bit 3) and mstatus.MIE.
 *
 * FreeRTOS (RISC-V port):
 *   #define configMTIME_BASE_ADDRESS     ANV32_CLINT_MTIME_ADDR
 *   #define configMTIMECMP_BASE_ADDRESS  ANV32_CLINT_MTIMECMP_ADDR
 *   #define configCPU_CLOCK_HZ           ANV32_MTIME_FREQ   (the tick math uses it)
 */

/* The SoC's MTIME_FREQ parameter (default 1 MHz: one mtime tick per microsecond) */
#ifndef ANV32_MTIME_FREQ
#define ANV32_MTIME_FREQ                1000000u
#endif

#define ANV32_CLINT_MSIP_OFFSET         0x0000u
#define ANV32_CLINT_MTIMECMP_OFFSET     0x4000u
#define ANV32_CLINT_MTIME_OFFSET        0xBFF8u

#define ANV32_CLINT_MSIP_ADDR           (ANV32_CLINT_BASE + ANV32_CLINT_MSIP_OFFSET)
#define ANV32_CLINT_MTIMECMP_ADDR       (ANV32_CLINT_BASE + ANV32_CLINT_MTIMECMP_OFFSET)
#define ANV32_CLINT_MTIME_ADDR          (ANV32_CLINT_BASE + ANV32_CLINT_MTIME_OFFSET)

#define ANV32_CLINT_MSIP                ANV32_REG32(ANV32_CLINT_MSIP_ADDR)
#define ANV32_CLINT_MTIMECMP_LO         ANV32_REG32(ANV32_CLINT_MTIMECMP_ADDR)
#define ANV32_CLINT_MTIMECMP_HI         ANV32_REG32(ANV32_CLINT_MTIMECMP_ADDR + 4u)
#define ANV32_CLINT_MTIME_LO            ANV32_REG32(ANV32_CLINT_MTIME_ADDR)
#define ANV32_CLINT_MTIME_HI            ANV32_REG32(ANV32_CLINT_MTIME_ADDR + 4u)

/* Read the 64-bit mtime: retry if the high word changed under the low read. */
static inline uint64_t anv32_mtime_read(void)
{
    uint32_t hi, lo;

    do {
        hi = ANV32_CLINT_MTIME_HI;
        lo = ANV32_CLINT_MTIME_LO;
    } while (hi != ANV32_CLINT_MTIME_HI);
    return ((uint64_t)hi << 32) | lo;
}

/*
 * Set mtimecmp without a spurious interrupt between the two 32-bit writes:
 * park the low word at its maximum first, so the intermediate value is never
 * below the target.
 */
static inline void anv32_mtimecmp_write(uint64_t value)
{
    ANV32_CLINT_MTIMECMP_LO = 0xFFFFFFFFu;
    ANV32_CLINT_MTIMECMP_HI = (uint32_t)(value >> 32);
    ANV32_CLINT_MTIMECMP_LO = (uint32_t)value;
}

#endif
