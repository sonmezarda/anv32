typedef int i32;

static volatile i32 a[16] = {
     3, -1,  4,  1,
     5,  9, -2,  6,
     5,  3,  5, -8,
     9,  7,  9,  3
};

static volatile i32 b[16] = {
     2,  7,  1,  8,
     2,  8,  1,  8,
     2,  8,  4,  5,
     9,  0,  4,  5
};

static volatile i32 c[16];

static i32 run_matrix_mul(void)
{
    i32 checksum = 0;

    for (int row = 0; row < 4; row++) {
        for (int col = 0; col < 4; col++) {
            i32 acc = 0;
            for (int k = 0; k < 4; k++) {
                acc += a[row * 4 + k] * b[k * 4 + col];
            }
            c[row * 4 + col] = acc;
            checksum += acc * (row + 3) + (acc ^ (col + 11));
        }
    }

    return checksum;
}

int main(void)
{
    return run_matrix_mul() == 6387;
}
