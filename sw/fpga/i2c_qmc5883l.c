#define LED_MMIO          (*(volatile unsigned int *)0x10000000u)
#define UART_TXDATA_MMIO  (*(volatile unsigned int *)0x10001000u)
#define UART_STATUS_MMIO  (*(volatile unsigned int *)0x10001004u)
#define UART_BAUD_MMIO    (*(volatile unsigned int *)0x10001008u)

#define I2C_CMD_MMIO      (*(volatile unsigned int *)0x10002000u)
#define I2C_STATUS_MMIO   (*(volatile unsigned int *)0x10002004u)
#define I2C_RXDATA_MMIO   (*(volatile unsigned int *)0x10002008u)
#define I2C_CTRL_MMIO     (*(volatile unsigned int *)0x1000200Cu)

#define UART_STATUS_TX_READY (1u << 0)

#define I2C_CMD_WRITE        0u
#define I2C_CMD_READ         1u
#define I2C_CMD_RECOVER      2u
#define I2C_CMD_START        (1u << 3)
#define I2C_CMD_STOP         (1u << 4)
#define I2C_CMD_ACK          (1u << 5)
#define I2C_CMD_DATA(x)      (((x) & 0xffu) << 8)

#define I2C_CTRL_CLEAR       (1u << 0)

#define I2C_STATUS_BUSY      (1u << 0)
#define I2C_STATUS_CMD_READY (1u << 1)
#define I2C_STATUS_RX_VALID  (1u << 2)
#define I2C_STATUS_DONE      (1u << 3)
#define I2C_STATUS_BUS_OWNED (1u << 4)
#define I2C_STATUS_BUS_FREE  (1u << 5)
#define I2C_STATUS_SDA       (1u << 6)
#define I2C_STATUS_SCL       (1u << 7)
#define I2C_STATUS_NACK      (1u << 16)
#define I2C_STATUS_ARB_LOST  (1u << 17)
#define I2C_STATUS_TIMEOUT   (1u << 18)
#define I2C_STATUS_BUS_BUSY  (1u << 19)
#define I2C_STATUS_RX_OVF    (1u << 20)
#define I2C_STATUS_CMD_OVF   (1u << 21)
#define I2C_STATUS_ILLEGAL   (1u << 22)
#define I2C_STATUS_REC_FAIL  (1u << 23)
#define I2C_STATUS_ERROR     (I2C_STATUS_NACK | I2C_STATUS_ARB_LOST | \
                              I2C_STATUS_TIMEOUT | I2C_STATUS_BUS_BUSY | \
                              I2C_STATUS_RX_OVF | I2C_STATUS_CMD_OVF | \
                              I2C_STATUS_ILLEGAL | I2C_STATUS_REC_FAIL)
#define I2C_STATUS_SW_TIMEOUT (1u << 31)

#define QMC5883L_ADDR 0x0du
#define I2C_WAIT_LIMIT 2000000u

// #section UART HELPER 
static void uart_putc(char c)
{
    while ((UART_STATUS_MMIO & UART_STATUS_TX_READY) == 0u) {
    }
    UART_TXDATA_MMIO = (unsigned int)c;
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
// #endregion
static void i2c_clear_status(void)
{
    I2C_CTRL_MMIO = I2C_CTRL_CLEAR;
}

static unsigned int i2c_wait_cmd_ready(void)
{
    unsigned int n;
    unsigned int status;

    for (n = 0; n < I2C_WAIT_LIMIT; n++) {
        status = I2C_STATUS_MMIO;
        if ((status & I2C_STATUS_CMD_READY) != 0u) {
            return status;
        }
    }

    return I2C_STATUS_MMIO | I2C_STATUS_SW_TIMEOUT;
}

static unsigned int i2c_wait_bus_done(void)
{
    unsigned int n;
    unsigned int status;

    for (n = 0; n < I2C_WAIT_LIMIT; n++) {
        status = I2C_STATUS_MMIO;
        if (((status & I2C_STATUS_BUSY) == 0u) &&
            ((status & I2C_STATUS_BUS_OWNED) == 0u) &&
            ((status & I2C_STATUS_BUS_FREE) != 0u)) {
            return status;
        }
    }

    return I2C_STATUS_MMIO | I2C_STATUS_SW_TIMEOUT;
}

static unsigned int i2c_wait_rx_valid(void)
{
    unsigned int n;
    unsigned int status;

    for (n = 0; n < I2C_WAIT_LIMIT; n++) {
        status = I2C_STATUS_MMIO;
        if ((status & I2C_STATUS_RX_VALID) != 0u) {
            return status;
        }
    }

    return I2C_STATUS_MMIO | I2C_STATUS_SW_TIMEOUT;
}

static unsigned int i2c_queue_cmd(unsigned int op, unsigned int flags, unsigned int data)
{
    unsigned int status;

    status = i2c_wait_cmd_ready();
    if ((status & I2C_STATUS_SW_TIMEOUT) != 0u) {
        return status;
    }

    I2C_CMD_MMIO = op | flags | I2C_CMD_DATA(data);
    return I2C_STATUS_MMIO;
}

static unsigned int i2c_recover_bus(void)
{
    unsigned int status;

    i2c_clear_status();
    status = i2c_queue_cmd(I2C_CMD_RECOVER, 0u, 0u);
    if ((status & I2C_STATUS_SW_TIMEOUT) != 0u) {
        return status;
    }

    return i2c_wait_bus_done();
}

static unsigned int i2c_write_reg(unsigned int addr, unsigned int reg, unsigned int value)
{
    unsigned int status;

    i2c_clear_status();
    status = i2c_queue_cmd(I2C_CMD_WRITE, I2C_CMD_START, (addr << 1) | 0u);
    if ((status & I2C_STATUS_SW_TIMEOUT) != 0u) return status;
    status = i2c_queue_cmd(I2C_CMD_WRITE, 0u, reg);
    if ((status & I2C_STATUS_SW_TIMEOUT) != 0u) return status;
    status = i2c_queue_cmd(I2C_CMD_WRITE, I2C_CMD_STOP, value);
    if ((status & I2C_STATUS_SW_TIMEOUT) != 0u) return status;

    return i2c_wait_bus_done();
}

static unsigned int i2c_reg_read(unsigned int addr, unsigned int reg,
                                 unsigned int len, unsigned char *buf)
{
    unsigned int i;
    unsigned int status;
    unsigned int flags;

    i2c_clear_status();
    status = i2c_queue_cmd(I2C_CMD_WRITE, I2C_CMD_START, (addr << 1) | 0u);
    if ((status & I2C_STATUS_SW_TIMEOUT) != 0u) return status;
    status = i2c_queue_cmd(I2C_CMD_WRITE, 0u, reg);
    if ((status & I2C_STATUS_SW_TIMEOUT) != 0u) return status;
    status = i2c_queue_cmd(I2C_CMD_WRITE, I2C_CMD_START, (addr << 1) | 1u);
    if ((status & I2C_STATUS_SW_TIMEOUT) != 0u) return status;

    for (i = 0; i < len; i++) {
        flags = (i + 1u == len) ? I2C_CMD_STOP : I2C_CMD_ACK;
        status = i2c_queue_cmd(I2C_CMD_READ, flags, 0u);
        if ((status & I2C_STATUS_SW_TIMEOUT) != 0u) return status;
        status = i2c_wait_rx_valid();
        if ((status & I2C_STATUS_SW_TIMEOUT) != 0u) return status;
        buf[i] = (unsigned char)(I2C_RXDATA_MMIO & 0xffu);
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

    UART_BAUD_MMIO = 115200u;
    LED_MMIO = 0x1u;
    uart_puts("ANV32 I2C QMC5883L CMD\r\n");
    data[0] = 0u;
    data[1] = 0u;
    data[2] = 0u;
    data[3] = 0u;
    data[4] = 0u;
    data[5] = 0u;

    status = I2C_STATUS_MMIO;
    if ((status & I2C_STATUS_BUS_FREE) == 0u) {
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

    if ((status & I2C_STATUS_ERROR) != 0u || id != 0xffu) {
        LED_MMIO = 0xEu;
        while (1) {
        }
    }

    LED_MMIO = 0x3u;

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

        LED_MMIO = (LED_MMIO == 0x3u) ? 0x5u : 0x3u;
    }
}
