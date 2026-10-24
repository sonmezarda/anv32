/*
 * GPIO interrupt path: a rising edge on gpio_irq_i sets IRQ_PENDING, raises
 * the machine external interrupt, and writing 1 clears it.
 */
#include "anv32_gpio.h"
#include "soc_test.h"

static volatile unsigned int irq_count;
static volatile unsigned int pending_in_handler;

__attribute__((interrupt("machine"), aligned(4)))
static void trap_handler(void)
{
    unsigned int mcause;

    __asm__ volatile ("csrr %0, mcause" : "=r"(mcause));
    if (mcause != 0x8000000Bu) {
        test_fail(2);
    }
    pending_in_handler = ANV32_GPIO0_IRQ_PENDING;
    ANV32_GPIO0_IRQ_PENDING = 1u;
    irq_count++;
}

int main(void)
{
    unsigned int timeout;

    __asm__ volatile ("csrw mtvec, %0" :: "r"(trap_handler));
    CHECK(ANV32_GPIO0_IRQ_PENDING == 0u, 3);

    /* Edge while interrupts are masked: pending is latched, nothing taken */
    ANV32_SYSCTRL_LED = SOC_TEST_GPIO_PULSE;
    timeout = 2000u;
    while (ANV32_GPIO0_IRQ_PENDING == 0u) {
        CHECK(--timeout != 0u, 4);
    }
    CHECK(irq_count == 0u, 5);

    /* Enabling takes the interrupt; the handler clears it */
    __asm__ volatile ("csrs mie, %0" :: "r"(1u << 11));
    __asm__ volatile ("csrsi mstatus, 8");
    CHECK(irq_count == 1u, 6);
    CHECK(pending_in_handler == 1u, 7);
    CHECK(ANV32_GPIO0_IRQ_PENDING == 0u, 8);

    /* A second edge with interrupts enabled */
    ANV32_SYSCTRL_LED = 0u;
    ANV32_SYSCTRL_LED = SOC_TEST_GPIO_PULSE;
    timeout = 2000u;
    while (irq_count != 2u) {
        CHECK(--timeout != 0u, 9);
    }

    test_pass();
    return 0;
}
