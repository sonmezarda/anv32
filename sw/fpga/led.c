#define LED_MMIO (*(volatile unsigned int *)0x10000000u)

int main(void)
{
    unsigned int value = 0;

    for (;;) {
        LED_MMIO = value++;

        for (volatile unsigned int delay = 0; delay < 400000u; delay++) {
        }
    }
}
