typedef int i32;

static volatile i32 samples[48] = {
     12, -7,  5,  9, -3,  4, 18, -11,
      6,  2, -9, 13,  7, -5,  1,  8,
    -14, 16,  3, -2, 10, -6, 11,  4,
     -1,  5, 17, -8,  9,  0, -4, 12,
      6, -3, 14, -7,  2,  8, -5, 15,
    -10,  1,  7, -2, 13, -6,  4,  9
};

static volatile i32 coeff[8] = {3, -1, 4, 1, -5, 9, -2, 6};
static volatile i32 output[41];

static i32 run_fir(void)
{
    i32 checksum = 0;

    for (int i = 0; i < 41; i++) {
        i32 acc = 0;
        for (int tap = 0; tap < 8; tap++) {
            acc += samples[i + tap] * coeff[tap];
        }
        output[i] = acc;
        checksum ^= acc + (i * 17);
        checksum += (acc << (i & 3));
    }

    return checksum;
}

int main(void)
{
    return run_fir() == 6711;
}
