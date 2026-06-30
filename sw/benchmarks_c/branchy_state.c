typedef unsigned int u32;

static volatile u32 stream[96] = {
    13,  1, 34,  8, 55,  2, 89,  3,
    21,  5,  1, 44,  7, 18, 29,  6,
    76, 11,  4, 90, 14,  0, 37,  9,
    58, 20,  2, 71, 12,  3, 43, 10,
    65, 15,  5, 82, 17,  6, 26, 19,
    97, 23,  7, 31, 25,  8, 49, 27,
    53, 30,  9, 61, 33, 10, 74, 35,
    86, 39, 11, 92, 41, 12, 16, 45,
    28, 47, 13, 40, 51, 14, 68, 57,
    80, 59, 15, 94, 63, 16, 22, 67,
    36, 69, 17, 50, 73, 18, 72, 79,
    84, 81, 19, 96, 85, 20, 24, 91
};

static u32 run_state_machine(void)
{
    u32 state = 0x12345678u;
    u32 acc = 0;

    for (int i = 0; i < 96; i++) {
        u32 x = stream[i];

        if ((x & 1u) == 0u) {
            state += x * 3u + 1u;
        } else if ((x & 3u) == 1u) {
            state ^= x + (state << 2);
        } else {
            state = (state >> 1) + (x << 5);
        }

        if (state & 0x80u) {
            acc += state ^ (x * 17u);
        } else {
            acc ^= state + x;
        }
    }

    return acc ^ state;
}

int main(void)
{
    return run_state_machine() == 0x731b16b6u;
}
