#include "anv32_nn.h"
#include "anv32_sysctrl.h"
#include "anv32_uart.h"

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
    (volatile unsigned int *)ANV32_NN_SCRATCH_BASE;

static void uart_putc(unsigned int c)
{
    while ((ANV32_UART0_STATUS & ANV32_UART_STATUS_TX_READY) == 0u) {
    }

    ANV32_UART0_TXDATA = c & 0xFFu;
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
    while ((ANV32_UART0_STATUS & ANV32_UART_STATUS_RX_VALID) == 0u) {
    }

    return ANV32_UART0_RXDATA & 0xFFu;
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
        pred = ANV32_NN_RESULT_ARGMAX & 0xFFu;
        best_score = ANV32_NN_BEST_SCORE;
        accel_cycles = ANV32_NN_CYCLE_COUNT;
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
    ANV32_NN_INPUT_BASE = INPUT_WORD_BASE * 4u;
    ANV32_NN_WEIGHT_BASE = WEIGHT_WORD_BASE * 4u;
    ANV32_NN_BIAS_BASE = BIAS_WORD_BASE * 4u;
    ANV32_NN_OUTPUT_BASE = OUTPUT_WORD_BASE * 4u;
    ANV32_NN_INPUT_LEN_WORDS = INPUT_WORDS;
    ANV32_NN_OUTPUT_COUNT = OUTPUTS;
    ANV32_NN_CONFIG = 0u;

    ANV32_NN_CONTROL = ANV32_NN_CONTROL_CLEAR;
    ANV32_NN_CONTROL = ANV32_NN_CONTROL_START;

    while ((ANV32_NN_STATUS &
            (ANV32_NN_STATUS_DONE | ANV32_NN_STATUS_ERROR)) == 0u) {
    }

    if ((ANV32_NN_STATUS & ANV32_NN_STATUS_ERROR) != 0u) {
        return ERR_ACCEL;
    }

    return ERR_OK;
}

int main(void)
{
    unsigned int magic;
    unsigned int status;
    unsigned int model_loaded = 0u;

    ANV32_UART0_BAUD = 115200u;
    ANV32_UART0_ERROR = 1u;
    ANV32_SYSCTRL_LED = 0x1u;
    uart_puts("ANV32_NN_UART_READY\n");

    for (;;) {
        magic = sync_to_magic();

        if (magic == MAGIC_MODEL) {
            status = receive_words(MODEL_WORDS, WEIGHT_WORD_BASE);

            if (status == ERR_OK) {
                model_loaded = 1u;
                ANV32_SYSCTRL_LED = 0x2u;
            } else {
                ANV32_SYSCTRL_LED = 0xEu;
            }

            send_model_ack(status);
        } else {
            status = receive_words(IMAGE_WORDS, INPUT_WORD_BASE);

            if (status == ERR_OK && model_loaded == 0u) {
                status = ERR_NO_MODEL;
            }

            if (status == ERR_OK) {
                ANV32_SYSCTRL_LED = 0x4u;
                status = run_accelerator();
            }

            if (status == ERR_OK) {
                ANV32_SYSCTRL_LED = ANV32_NN_RESULT_ARGMAX & 0xFu;
            } else {
                ANV32_SYSCTRL_LED = 0xEu;
            }

            send_response(status);
        }
    }
}
