#include "uart_lib.h"

#include "anv32_uart.h"

const anv32_uart_t UART0 = {
    .base = ANV32_UART0_BASE,
};

void uart_begin(const anv32_uart_t *uart, unsigned int baud)
{
    ANV32_UART_BAUD(uart->base) = baud;
}

void uart_putc(const anv32_uart_t *uart, char c)
{
    while ((ANV32_UART_STATUS(uart->base) &
            ANV32_UART_STATUS_TX_READY) == 0u) {
    }

    ANV32_UART_TXDATA(uart->base) = (unsigned int)(unsigned char)c;
}

void uart_puts(const anv32_uart_t *uart, const char *s)
{
    while (*s != '\0') {
        uart_putc(uart, *s);
        s++;
    }
}

int uart_available(const anv32_uart_t *uart)
{
    return (ANV32_UART_STATUS(uart->base) &
            ANV32_UART_STATUS_RX_VALID) != 0u;
}

unsigned char uart_getc(const anv32_uart_t *uart)
{
    while (!uart_available(uart)) {
    }

    return (unsigned char)(ANV32_UART_RXDATA(uart->base) & 0xFFu);
}
