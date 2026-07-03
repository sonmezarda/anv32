#define LED_MMIO             (*(volatile unsigned int *)0x10000000u)

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

#define NN_STATUS_DONE       (1u << 1)
#define NN_STATUS_ERROR      (1u << 2)
#define NN_CONTROL_START     (1u << 0)
#define NN_CONTROL_CLEAR     (1u << 1)

static volatile unsigned int *const nn_scratch =
    (volatile unsigned int *)NN_SCRATCH_BASE;

int main(void)
{
    enum {
        INPUT_WORD  = 0,
        WEIGHT_WORD = 1,
        BIAS_WORD   = 4,
        OUTPUT_WORD = 8
    };

    LED_MMIO = 0x1u;

    /*
     * One 4-lane int8 input vector:
     *   x = [2, -1, 3, 4]
     *
     * Three neurons:
     *   y0 = dot(x, [ 1,  1, 1, 1]) +  0 =  8
     *   y1 = dot(x, [-1,  2, 0, 1]) +  5 =  5
     *   y2 = dot(x, [ 4, -3, 2, 1]) + -1 = 20
     *
     * Expected argmax is neuron 2.
     */
    nn_scratch[INPUT_WORD + 0] = 0x0403FF02u;

    nn_scratch[WEIGHT_WORD + 0] = 0x01010101u;
    nn_scratch[WEIGHT_WORD + 1] = 0x010002FFu;
    nn_scratch[WEIGHT_WORD + 2] = 0x0102FD04u;

    nn_scratch[BIAS_WORD + 0] = 0x00000000u;
    nn_scratch[BIAS_WORD + 1] = 0x00000005u;
    nn_scratch[BIAS_WORD + 2] = 0xFFFFFFFFu;

    NN_INPUT_BASE = INPUT_WORD * 4u;
    NN_WEIGHT_BASE = WEIGHT_WORD * 4u;
    NN_BIAS_BASE = BIAS_WORD * 4u;
    NN_OUTPUT_BASE = OUTPUT_WORD * 4u;
    NN_INPUT_LEN_WORDS = 1u;
    NN_OUTPUT_COUNT = 3u;
    NN_CONFIG = 0u;

    NN_CONTROL = NN_CONTROL_CLEAR;
    NN_CONTROL = NN_CONTROL_START;

    while ((NN_STATUS & (NN_STATUS_DONE | NN_STATUS_ERROR)) == 0u) {
    }

    if ((NN_STATUS & NN_STATUS_ERROR) != 0u) {
        LED_MMIO = 0xEu;
    } else if (NN_RESULT_ARGMAX == 2u && NN_BEST_SCORE == 20u) {
        LED_MMIO = 0x2u;
    } else {
        LED_MMIO = 0xFu;
    }

    for (;;) {
    }
}
