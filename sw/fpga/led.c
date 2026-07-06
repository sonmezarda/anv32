#include "anv32_sysctrl.h"

int main(void)
{
    unsigned int value = 0;

    for (;;) {
        ANV32_SYSCTRL_LED = value++;

        for (volatile unsigned int delay = 0; delay < 400000u; delay++) {
        }
    }
}
