typedef unsigned int u32;

static volatile u32 src[64];
static volatile u32 dst[64];

static u32 run_copy(void)
{
    u32 checksum = 0;

    for (int i = 0; i < 64; i++) {
        src[i] = 0x9e3779b9u * (u32)(i + 1) ^ ((u32)i << 16);
    }

    for (int pass = 0; pass < 4; pass++) {
        for (int i = 0; i < 64; i++) {
            dst[i] = src[(i + pass) & 63] + (u32)pass;
        }
        for (int i = 0; i < 64; i++) {
            checksum ^= dst[i] + (checksum << 5) + (checksum >> 2);
        }
    }

    return checksum;
}

int main(void)
{
    return run_copy() == 0x03a48818u;
}
