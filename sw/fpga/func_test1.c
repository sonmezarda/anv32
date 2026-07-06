#include "anv32_sysctrl.h"

int main(void)
{
    unsigned int value = 0;

    for (;;) {
        ANV32_SYSCTRL_LED = value++;

        delay(400000u);
    }
}

void delay(unsigned int delay_count){
    for(volatile unsigned int i=0; i <delay_count; i++){}
}
