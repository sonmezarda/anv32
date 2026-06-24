#define LED_MMIO (*(volatile unsigned int *)0x10000000u)

int main(void)
{
    unsigned int value = 0xA;
    int a =  5;
    int b = -10;

    int c = a * b;

    if(c != -50)
        LED_MMIO = value;
    else 
        LED_MMIO = 0b1100;
}
