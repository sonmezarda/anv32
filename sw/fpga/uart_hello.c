#include "anv32_sysctrl.h"
#include "anv32_uart.h"

static void uart_putc(char c)
{
    while ((ANV32_UART0_STATUS & ANV32_UART_STATUS_TX_READY) == 0u) {
    }

    ANV32_UART0_TXDATA = (unsigned int)c;
}

static void uart_puts(const char *s)
{
    while (*s != '\0') {
        uart_putc(*s++);
    }
}

int main(void)
{
    ANV32_UART0_BAUD = 115200u;
    ANV32_SYSCTRL_LED = 0x1u;

    for (;;) {
        uart_puts("ANV32 UART hello\r\n");
        ANV32_SYSCTRL_LED = 0x5u;

        for (volatile unsigned int delay = 0; delay < 1000000u; delay++) {
        }

        ANV32_SYSCTRL_LED = 0xAu;
    }
}
