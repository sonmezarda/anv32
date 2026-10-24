#include "anv32_i2c.h"
#include "anv32_sysctrl.h"
#include "anv32_uart.h"

#define QMC5883L_ADDR 0x0du
#define I2C_WAIT_LIMIT 2000000u

// UART helpers
static void uart_putc(char c)
{
    while ((ANV32_UART0_STATUS & ANV32_UART_STATUS_TX_READY) == 0u) {
    }
    ANV32_UART0_TXDATA = (unsigned int)c;
}

static void uart_puts(const char *s)
{
    while (*s) {
        uart_putc(*s++);
    }
}

static void uart_puthex4(unsigned int v)
{
    v &= 0xfu;
    uart_putc((char)(v < 10u ? ('0' + v) : ('A' + (v - 10u))));
}

static void uart_puthex8(unsigned int v)
{
    uart_puthex4(v >> 4);
    uart_puthex4(v);
}

static void uart_puthex16(unsigned int v)
{
    uart_puthex8(v >> 8);
    uart_puthex8(v);
}

static void uart_puthex32(unsigned int v)
{
    uart_puthex16(v >> 16);
    uart_puthex16(v);
}

static void i2c_clear_status(void)
{
    ANV32_I2C0_CTRL = ANV32_I2C_CTRL_CLEAR;
}

static unsigned int i2c_wait_cmd_ready(void)
{
    unsigned int n;
    unsigned int status;

    for (n = 0; n < I2C_WAIT_LIMIT; n++) {
        status = ANV32_I2C0_STATUS;
        if ((status & ANV32_I2C_STATUS_CMD_READY) != 0u) {
            return status;
        }
    }

    return ANV32_I2C0_STATUS | ANV32_I2C_STATUS_SW_TIMEOUT;
}

static unsigned int i2c_wait_bus_done(void)
{
    unsigned int n;
    unsigned int status;

    for (n = 0; n < I2C_WAIT_LIMIT; n++) {
        status = ANV32_I2C0_STATUS;
        if (((status & ANV32_I2C_STATUS_BUSY) == 0u) &&
            ((status & ANV32_I2C_STATUS_BUS_OWNED) == 0u) &&
            ((status & ANV32_I2C_STATUS_BUS_FREE) != 0u)) {
            return status;
        }
    }

    return ANV32_I2C0_STATUS | ANV32_I2C_STATUS_SW_TIMEOUT;
}

static unsigned int i2c_wait_rx_valid(void)
{
    unsigned int n;
    unsigned int status;

    for (n = 0; n < I2C_WAIT_LIMIT; n++) {
        status = ANV32_I2C0_STATUS;
        if ((status & ANV32_I2C_STATUS_RX_VALID) != 0u) {
            return status;
        }
    }

    return ANV32_I2C0_STATUS | ANV32_I2C_STATUS_SW_TIMEOUT;
}

static unsigned int i2c_queue_cmd(unsigned int op, unsigned int flags, unsigned int data)
{
    unsigned int status;

    status = i2c_wait_cmd_ready();
    if ((status & ANV32_I2C_STATUS_SW_TIMEOUT) != 0u) {
        return status;
    }

    ANV32_I2C0_CMD = op | flags | ANV32_I2C_CMD_DATA(data);
    return ANV32_I2C0_STATUS;
}

static unsigned int i2c_recover_bus(void)
{
    unsigned int status;

    i2c_clear_status();
    status = i2c_queue_cmd(ANV32_I2C_CMD_RECOVER, 0u, 0u);
    if ((status & ANV32_I2C_STATUS_SW_TIMEOUT) != 0u) {
        return status;
    }

    return i2c_wait_bus_done();
}

static unsigned int i2c_write_reg(unsigned int addr, unsigned int reg, unsigned int value)
{
    unsigned int status;

    i2c_clear_status();
    status = i2c_queue_cmd(ANV32_I2C_CMD_WRITE, ANV32_I2C_CMD_START, (addr << 1) | 0u);
    if ((status & ANV32_I2C_STATUS_SW_TIMEOUT) != 0u) return status;
    status = i2c_queue_cmd(ANV32_I2C_CMD_WRITE, 0u, reg);
    if ((status & ANV32_I2C_STATUS_SW_TIMEOUT) != 0u) return status;
    status = i2c_queue_cmd(ANV32_I2C_CMD_WRITE, ANV32_I2C_CMD_STOP, value);
    if ((status & ANV32_I2C_STATUS_SW_TIMEOUT) != 0u) return status;

    return i2c_wait_bus_done();
}

static unsigned int i2c_reg_read(unsigned int addr, unsigned int reg,
                                 unsigned int len, unsigned char *buf)
{
    unsigned int i;
    unsigned int status;
    unsigned int flags;

    i2c_clear_status();
    status = i2c_queue_cmd(ANV32_I2C_CMD_WRITE, ANV32_I2C_CMD_START, (addr << 1) | 0u);
    if ((status & ANV32_I2C_STATUS_SW_TIMEOUT) != 0u) return status;
    status = i2c_queue_cmd(ANV32_I2C_CMD_WRITE, 0u, reg);
    if ((status & ANV32_I2C_STATUS_SW_TIMEOUT) != 0u) return status;
    status = i2c_queue_cmd(ANV32_I2C_CMD_WRITE, ANV32_I2C_CMD_START, (addr << 1) | 1u);
    if ((status & ANV32_I2C_STATUS_SW_TIMEOUT) != 0u) return status;

    for (i = 0; i < len; i++) {
        flags = (i + 1u == len) ? ANV32_I2C_CMD_STOP : ANV32_I2C_CMD_ACK;
        status = i2c_queue_cmd(ANV32_I2C_CMD_READ, flags, 0u);
        if ((status & ANV32_I2C_STATUS_SW_TIMEOUT) != 0u) return status;
        status = i2c_wait_rx_valid();
        if ((status & ANV32_I2C_STATUS_SW_TIMEOUT) != 0u) return status;
        buf[i] = (unsigned char)(ANV32_I2C0_RXDATA & 0xffu);
    }

    status = i2c_wait_bus_done();
    return status;
}

static void delay(volatile unsigned int n)
{
    while (n--) {
    }
}

int main(void)
{
    unsigned int status;
    unsigned int id;
    unsigned int x;
    unsigned int y;
    unsigned int z;
    unsigned char data[6];

    ANV32_UART0_BAUD = 115200u;
    ANV32_SYSCTRL_LED = 0x1u;
    uart_puts("ANV32 I2C QMC5883L CMD\r\n");
    data[0] = 0u;
    data[1] = 0u;
    data[2] = 0u;
    data[3] = 0u;
    data[4] = 0u;
    data[5] = 0u;

    status = ANV32_I2C0_STATUS;
    if ((status & ANV32_I2C_STATUS_BUS_FREE) == 0u) {
        status = i2c_recover_bus();
        uart_puts("recover st=");
        uart_puthex32(status);
        uart_puts("\r\n");
    }

    status = i2c_reg_read(QMC5883L_ADDR, 0x0du, 1u, data);
    id = data[0];

    uart_puts("ID=");
    uart_puthex8(id);
    uart_puts(" status=");
    uart_puthex32(status);
    uart_puts("\r\n");

    if ((status & ANV32_I2C_STATUS_ERROR) != 0u || id != 0xffu) {
        ANV32_SYSCTRL_LED = 0xEu;
        while (1) {
        }
    }

    ANV32_SYSCTRL_LED = 0x3u;

    i2c_write_reg(QMC5883L_ADDR, 0x0bu, 0x01u);
    i2c_write_reg(QMC5883L_ADDR, 0x09u, 0x1du);

    while (1) {
        delay(500000u);

        status = i2c_reg_read(QMC5883L_ADDR, 0x00u, 6u, data);

        x = ((unsigned int)data[0]) | (((unsigned int)data[1]) << 8);
        y = ((unsigned int)data[2]) | (((unsigned int)data[3]) << 8);
        z = ((unsigned int)data[4]) | (((unsigned int)data[5]) << 8);

        uart_puts("XYZ ");
        uart_puthex16(x);
        uart_putc(' ');
        uart_puthex16(y);
        uart_putc(' ');
        uart_puthex16(z);
        uart_puts(" st=");
        uart_puthex32(status);
        uart_puts("\r\n");

        ANV32_SYSCTRL_LED = (ANV32_SYSCTRL_LED == 0x3u) ? 0x5u : 0x3u;
    }
}
