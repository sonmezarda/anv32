#define LED_MMIO          (*(volatile unsigned int *)0x10000000u)
#define UART_TXDATA_MMIO  (*(volatile unsigned int *)0x10001000u)
#define UART_STATUS_MMIO  (*(volatile unsigned int *)0x10001004u)
#define UART_BAUD_MMIO    (*(volatile unsigned int *)0x10001008u)

#define UART_STATUS_TX_READY (1u << 0)

static void uart_putc(char c)
{
    while ((UART_STATUS_MMIO & UART_STATUS_TX_READY) == 0u) {
    }

    UART_TXDATA_MMIO = (unsigned int)c;
}

static void uart_puts(const char *s)
{
    while (*s != '\0') {
        uart_putc(*s++);
    }
}

int main(void)
{
    UART_BAUD_MMIO = 115200u;
    LED_MMIO = 0x1u;

    for (;;) {
        uart_puts("ANV32 UART hello\r\n");
        LED_MMIO = 0x5u;

        for (volatile unsigned int delay = 0; delay < 1000000u; delay++) {
        }

        LED_MMIO = 0xAu;
    }
}
