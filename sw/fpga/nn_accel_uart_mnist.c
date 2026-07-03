#define LED_MMIO             (*(volatile unsigned int *)0x10000000u)

#define UART_TXDATA_MMIO     (*(volatile unsigned int *)0x10001000u)
#define UART_STATUS_MMIO     (*(volatile unsigned int *)0x10001004u)
#define UART_BAUD_MMIO       (*(volatile unsigned int *)0x10001008u)
#define UART_ERROR_MMIO      (*(volatile unsigned int *)0x1000100Cu)
#define UART_RXDATA_MMIO     (*(volatile unsigned int *)0x10001010u)

#define UART_STATUS_TX_READY (1u << 0)
#define UART_STATUS_RX_VALID (1u << 4)

#define NN_BASE              0x10003000u
#define NN_SCRATCH_BASE      (NN_BASE + 0x1000u)

#define NN_CONTROL           (*(volatile unsigned int *)(NN_BASE + 0x00u))
#define NN_STATUS            (*(volatile unsigned int *)(NN_BASE + 0x04u))
#define NN_INPUT_BASE        (*(volatile unsigned int *)(NN_BASE + 0x08u))
#define NN_WEIGHT_BASE       (*(volatile unsigned int *)(NN_BASE + 0x0Cu))
#define NN_BIAS_BASE         (*(volatile unsigned int *)(NN_BASE + 0x10u))
#define NN_OUTPUT_BASE       (*(volatile unsigned int *)(NN_BASE + 0x14u))
#define NN_INPUT_LEN_WORDS   (*(volatile unsigned int *)(NN_BASE + 0x18u))
#define NN_OUTPUT_COUNT      (*(volatile unsigned int *)(NN_BASE + 0x1Cu))
#define NN_CONFIG            (*(volatile unsigned int *)(NN_BASE + 0x20u))
#define NN_RESULT_ARGMAX     (*(volatile unsigned int *)(NN_BASE + 0x24u))
#define NN_BEST_SCORE        (*(volatile unsigned int *)(NN_BASE + 0x28u))
#define NN_CYCLE_COUNT       (*(volatile unsigned int *)(NN_BASE + 0x2Cu))

#define NN_STATUS_DONE       (1u << 1)
#define NN_STATUS_ERROR      (1u << 2)
#define NN_CONTROL_START     (1u << 0)
#define NN_CONTROL_CLEAR     (1u << 1)

#define INPUT_WORDS          196u
#define OUTPUTS              10u
#define INPUT_WORD_BASE      0u
#define WEIGHT_WORD_BASE     256u
#define BIAS_WORD_BASE       (WEIGHT_WORD_BASE + OUTPUTS * INPUT_WORDS)
#define OUTPUT_WORD_BASE     (BIAS_WORD_BASE + OUTPUTS)

/* Weights and biases are contiguous in scratch, so one model packet fills
 * WEIGHT_WORD_BASE..BIAS_WORD_BASE+OUTPUTS-1 in a single stream. */
#define MODEL_WORDS          (OUTPUTS * INPUT_WORDS + OUTPUTS)
#define IMAGE_WORDS          INPUT_WORDS

#define MAGIC_MODEL          0x4E4E4D31u /* "NNM1" */
#define MAGIC_IMAGE          0x4E4E4931u /* "NNI1" */

#define ERR_OK               0u
#define ERR_MAGIC            1u
#define ERR_COUNT            2u
#define ERR_CHECKSUM         3u
#define ERR_ACCEL            4u
#define ERR_NO_MODEL         5u

static volatile unsigned int *const nn_scratch =
    (volatile unsigned int *)NN_SCRATCH_BASE;

static void uart_putc(unsigned int c)
{
    while ((UART_STATUS_MMIO & UART_STATUS_TX_READY) == 0u) {
    }

    UART_TXDATA_MMIO = c & 0xFFu;
}

static void uart_puts(const char *s)
{
    while (*s != '\0') {
        uart_putc((unsigned int)*s);
        s++;
    }
}

static unsigned int uart_getc(void)
{
    while ((UART_STATUS_MMIO & UART_STATUS_RX_VALID) == 0u) {
    }

    return UART_RXDATA_MMIO & 0xFFu;
}

static void put_u16_le(unsigned int value)
{
    uart_putc(value);
    uart_putc(value >> 8);
}

static void put_u32_le(unsigned int value)
{
    uart_putc(value);
    uart_putc(value >> 8);
    uart_putc(value >> 16);
    uart_putc(value >> 24);
}

static unsigned int get_u16_le(void)
{
    unsigned int b0 = uart_getc();
    unsigned int b1 = uart_getc();

    return b0 | (b1 << 8);
}

static unsigned int get_u32_le(void)
{
    unsigned int b0 = uart_getc();
    unsigned int b1 = uart_getc();
    unsigned int b2 = uart_getc();
    unsigned int b3 = uart_getc();

    return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
}

static unsigned int get_payload_word(unsigned int *checksum)
{
    unsigned int b0 = uart_getc();
    unsigned int b1 = uart_getc();
    unsigned int b2 = uart_getc();
    unsigned int b3 = uart_getc();

    *checksum += b0 + b1 + b2 + b3;

    return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
}

static unsigned int scratch_read_word(unsigned int word_addr)
{
    return nn_scratch[word_addr];
}

/* Slide a 4-byte window over the RX stream until it equals one of the packet
 * magics, so stray bytes before or between packets cannot desynchronize the
 * receiver. Returns the matched magic. */
static unsigned int sync_to_magic(void)
{
    unsigned int window = 0u;

    for (;;) {
        window = (window << 8) | uart_getc();

        if (window == MAGIC_MODEL || window == MAGIC_IMAGE) {
            return window;
        }
    }
}

/* Read the count/checksum header and a word payload into scratch. */
static unsigned int receive_words(unsigned int expected_count,
                                  unsigned int scratch_word_base)
{
    unsigned int count;
    unsigned int expected_checksum;
    unsigned int checksum = 0u;

    count = get_u16_le();
    expected_checksum = get_u32_le();

    if (count != expected_count) {
        return ERR_COUNT;
    }

    for (unsigned int i = 0; i < expected_count; i++) {
        nn_scratch[scratch_word_base + i] = get_payload_word(&checksum);
    }

    if (checksum != expected_checksum) {
        return ERR_CHECKSUM;
    }

    return ERR_OK;
}

static void send_model_ack(unsigned int status)
{
    uart_putc('N');
    uart_putc('N');
    uart_putc('A');
    uart_putc('1');
    uart_putc(status);
    uart_putc(0u);
    put_u16_le(0u);
}

static void send_response(unsigned int status)
{
    unsigned int pred = 0u;
    unsigned int best_score = 0u;
    unsigned int accel_cycles = 0u;

    if (status == ERR_OK) {
        pred = NN_RESULT_ARGMAX & 0xFFu;
        best_score = NN_BEST_SCORE;
        accel_cycles = NN_CYCLE_COUNT;
    }

    uart_putc('N');
    uart_putc('N');
    uart_putc('R');
    uart_putc('1');
    uart_putc(status);
    uart_putc(pred);
    put_u16_le(0u);
    put_u32_le(best_score);
    put_u32_le(accel_cycles);

    for (unsigned int i = 0; i < OUTPUTS; i++) {
        if (status == ERR_OK) {
            put_u32_le(scratch_read_word(OUTPUT_WORD_BASE + i));
        } else {
            put_u32_le(0u);
        }
    }
}

static unsigned int run_accelerator(void)
{
    NN_INPUT_BASE = INPUT_WORD_BASE * 4u;
    NN_WEIGHT_BASE = WEIGHT_WORD_BASE * 4u;
    NN_BIAS_BASE = BIAS_WORD_BASE * 4u;
    NN_OUTPUT_BASE = OUTPUT_WORD_BASE * 4u;
    NN_INPUT_LEN_WORDS = INPUT_WORDS;
    NN_OUTPUT_COUNT = OUTPUTS;
    NN_CONFIG = 0u;

    NN_CONTROL = NN_CONTROL_CLEAR;
    NN_CONTROL = NN_CONTROL_START;

    while ((NN_STATUS & (NN_STATUS_DONE | NN_STATUS_ERROR)) == 0u) {
    }

    if ((NN_STATUS & NN_STATUS_ERROR) != 0u) {
        return ERR_ACCEL;
    }

    return ERR_OK;
}

int main(void)
{
    unsigned int magic;
    unsigned int status;
    unsigned int model_loaded = 0u;

    UART_BAUD_MMIO = 115200u;
    UART_ERROR_MMIO = 1u;
    LED_MMIO = 0x1u;
    uart_puts("ANV32_NN_UART_READY\n");

    for (;;) {
        magic = sync_to_magic();

        if (magic == MAGIC_MODEL) {
            status = receive_words(MODEL_WORDS, WEIGHT_WORD_BASE);

            if (status == ERR_OK) {
                model_loaded = 1u;
                LED_MMIO = 0x2u;
            } else {
                LED_MMIO = 0xEu;
            }

            send_model_ack(status);
        } else {
            status = receive_words(IMAGE_WORDS, INPUT_WORD_BASE);

            if (status == ERR_OK && model_loaded == 0u) {
                status = ERR_NO_MODEL;
            }

            if (status == ERR_OK) {
                LED_MMIO = 0x4u;
                status = run_accelerator();
            }

            if (status == ERR_OK) {
                LED_MMIO = NN_RESULT_ARGMAX & 0xFu;
            } else {
                LED_MMIO = 0xEu;
            }

            send_response(status);
        }
    }
}
