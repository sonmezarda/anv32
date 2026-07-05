#ifndef UART_LIB_H
#define UART_LIB_H

typedef struct {
    unsigned int base;
} anv32_uart_t;

extern const anv32_uart_t UART0;

void uart_begin(const anv32_uart_t *uart, unsigned int baud);
void uart_putc(const anv32_uart_t *uart, char c);
void uart_puts(const anv32_uart_t *uart, const char *s);
int uart_available(const anv32_uart_t *uart);
unsigned char uart_getc(const anv32_uart_t *uart);

#endif
