/*
 * CLINT on the SoC: mtime counts at MTIME_FREQ (tb_soc_test: 27 MHz clock,
 * 1 MHz mtime, so one tick every 27 clocks), a timer interrupt through
 * mtimecmp and a software interrupt through msip, both through a C handler.
 * Uses the helpers in anv32_clint.h. Needs a core with the CLINT interrupts.
 */
#include "anv32_clint.h"
#include "soc_test.h"

#define CLOCKS_PER_TICK     27u

static volatile unsigned int timer_count;
static volatile unsigned int sw_count;

__attribute__((interrupt("machine"), aligned(4)))
static void trap_handler(void)
{
    unsigned int mcause;

    __asm__ volatile ("csrr %0, mcause" : "=r"(mcause));
    if (mcause == 0x80000007u) {
        anv32_mtimecmp_write(UINT64_MAX);   /* one shot: park the timer */
        timer_count++;
    } else if (mcause == 0x80000003u) {
        ANV32_CLINT_MSIP = 0u;
        sw_count++;
    } else {
        test_fail(2);
    }
}

static inline uint32_t read_mcycle(void)
{
    uint32_t v;

    __asm__ volatile ("csrr %0, mcycle" : "=r"(v));
    return v;
}

static void wait_ticks(uint32_t ticks)
{
    uint64_t start = anv32_mtime_read();

    while (anv32_mtime_read() - start < ticks) {
    }
}

int main(void)
{
    uint64_t t0;
    uint32_t c0, c1, timeout;

    __asm__ volatile ("csrw mtvec, %0" :: "r"(trap_handler));

    /* mtime runs at MTIME_FREQ: 20 ticks take about 20 * 27 clocks */
    t0 = anv32_mtime_read();
    c0 = read_mcycle();
    while (anv32_mtime_read() - t0 < 20u) {
    }
    c1 = read_mcycle();
    CHECK(c1 - c0 >= 19u * CLOCKS_PER_TICK, 3);
    CHECK(c1 - c0 <= 21u * CLOCKS_PER_TICK + 100u, 4);

    /* Timer interrupt 50 ticks from now; the handler parks mtimecmp */
    anv32_mtimecmp_write(anv32_mtime_read() + 50u);
    __asm__ volatile ("csrs mie, %0" :: "r"(1u << 7));
    __asm__ volatile ("csrsi mstatus, 8");
    CHECK(timer_count == 0u, 5);
    timeout = 100000u;
    while (timer_count == 0u) {
        CHECK(--timeout != 0u, 6);
    }
    wait_ticks(100u);
    CHECK(timer_count == 1u, 7);

    /* Software interrupt: the handler clears msip */
    __asm__ volatile ("csrs mie, %0" :: "r"(1u << 3));
    ANV32_CLINT_MSIP = 1u;
    timeout = 1000u;
    while (sw_count == 0u) {
        CHECK(--timeout != 0u, 8);
    }
    CHECK(sw_count == 1u, 9);
    CHECK(ANV32_CLINT_MSIP == 0u, 10);

    test_pass();
    return 0;
}
