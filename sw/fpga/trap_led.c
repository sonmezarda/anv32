#include "anv32_sysctrl.h"

volatile unsigned int trap_flags;

void trap_handler(void);

static inline void write_mtvec(unsigned int value)
{
    __asm__ volatile ("csrw mtvec, %0" :: "r"(value) : "memory");
}

static inline void trigger_ecall(void)
{
    __asm__ volatile ("ecall" ::: "memory");
}

static inline void trigger_illegal(void)
{
    __asm__ volatile (".word 0xffffffff" ::: "memory");
}

static void delay(unsigned int count)
{
    for (volatile unsigned int i = 0; i < count; i++) {
    }
}

static void blink_pass(void)
{
    for (;;) {
        ANV32_SYSCTRL_LED = 0x0a;
        delay(400000u);
        ANV32_SYSCTRL_LED = 0x05;
        delay(400000u);
    }
}

static void show_fail(unsigned int code)
{
    for (;;) {
        ANV32_SYSCTRL_LED = code;
    }
}

int main(void)
{
    trap_flags = 0;
    write_mtvec((unsigned int)trap_handler);

    trigger_ecall();
    if (trap_flags != 1u) {
        show_fail(1u);
    }

    trigger_illegal();
    if (trap_flags != 3u) {
        show_fail(2u);
    }

    blink_pass();
}

__attribute__((naked, used, aligned(4)))
void trap_handler(void)
{
    __asm__ volatile (
        "csrr t0, mcause\n"
        "addi t1, zero, 11\n"
        "beq  t0, t1, 1f\n"
        "addi t1, zero, 2\n"
        "beq  t0, t1, 2f\n"

        "la   t2, trap_flags\n"
        "addi t3, zero, 14\n"
        "sw   t3, 0(t2)\n"
        "j    3f\n"

        "1:\n"
        "la   t2, trap_flags\n"
        "lw   t3, 0(t2)\n"
        "ori  t3, t3, 1\n"
        "sw   t3, 0(t2)\n"
        "j    3f\n"

        "2:\n"
        "la   t2, trap_flags\n"
        "lw   t3, 0(t2)\n"
        "ori  t3, t3, 2\n"
        "sw   t3, 0(t2)\n"

        "3:\n"
        "csrr t0, mepc\n"
        "addi t0, t0, 4\n"
        "csrw mepc, t0\n"
        "mret"
    );
}
