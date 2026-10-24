/*
 * UART TX -> RX loopback (wired in tb_soc_test.sv) through both FIFOs.
 */
#include "anv32_uart.h"
#include "soc_test.h"

static const char message[] = "anv32 uart\n";

int main(void)
{
    unsigned int i;
    unsigned int timeout;

    ANV32_UART0_BAUD = 1000000u;

    /* Fill the TX FIFO, then read everything back */
    for (i = 0; message[i] != '\0'; i++) {
        while ((ANV32_UART0_STATUS & ANV32_UART_STATUS_TX_READY) == 0u) {
        }
        ANV32_UART0_TXDATA = (unsigned char)message[i];
    }

    for (i = 0; message[i] != '\0'; i++) {
        timeout = 20000u;
        while ((ANV32_UART0_STATUS & ANV32_UART_STATUS_RX_VALID) == 0u) {
            CHECK(--timeout != 0u, 2);
        }
        CHECK(ANV32_UART0_RXDATA == (unsigned char)message[i], 10 + i);
    }

    CHECK((ANV32_UART0_STATUS & ANV32_UART_STATUS_RX_EMPTY) != 0u, 3);
    CHECK(ANV32_UART0_ERROR == 0u, 4);

    test_pass();
    return 0;
}
