#include "anv32_nn.h"
#include "anv32_sysctrl.h"

static volatile unsigned int *const nn_scratch =
    (volatile unsigned int *)ANV32_NN_SCRATCH_BASE;

int main(void)
{
    enum {
        INPUT_WORD  = 0,
        WEIGHT_WORD = 1,
        BIAS_WORD   = 4,
        OUTPUT_WORD = 8
    };

    ANV32_SYSCTRL_LED = 0x1u;

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

    ANV32_NN_INPUT_BASE = INPUT_WORD * 4u;
    ANV32_NN_WEIGHT_BASE = WEIGHT_WORD * 4u;
    ANV32_NN_BIAS_BASE = BIAS_WORD * 4u;
    ANV32_NN_OUTPUT_BASE = OUTPUT_WORD * 4u;
    ANV32_NN_INPUT_LEN_WORDS = 1u;
    ANV32_NN_OUTPUT_COUNT = 3u;
    ANV32_NN_CONFIG = 0u;

    ANV32_NN_CONTROL = ANV32_NN_CONTROL_CLEAR;
    ANV32_NN_CONTROL = ANV32_NN_CONTROL_START;

    while ((ANV32_NN_STATUS &
            (ANV32_NN_STATUS_DONE | ANV32_NN_STATUS_ERROR)) == 0u) {
    }

    if ((ANV32_NN_STATUS & ANV32_NN_STATUS_ERROR) != 0u) {
        ANV32_SYSCTRL_LED = 0xEu;
    } else if (ANV32_NN_RESULT_ARGMAX == 2u && ANV32_NN_BEST_SCORE == 20u) {
        ANV32_SYSCTRL_LED = 0x2u;
    } else {
        ANV32_SYSCTRL_LED = 0xFu;
    }

    for (;;) {
    }
}
