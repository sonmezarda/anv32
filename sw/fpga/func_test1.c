#define LED_MMIO (*(volatile unsigned int *)0x10000000u)

int main(void)
{
    unsigned int value = 0;

    for (;;) {
        LED_MMIO = value++;

        delay(400000u);
    }
}

void delay(unsigned int delay_count){
    for(volatile unsigned int i=0; i <delay_count; i++){}
}
