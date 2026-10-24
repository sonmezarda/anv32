/*
 * riscv-arch-test model macros for anv32, shared by the cores and by Spike
 * (the reference). A test ends by writing 1 to tohost; the signature lies
 * between begin_signature and end_signature.
 */
#ifndef ANV32_MODEL_TEST_H
#define ANV32_MODEL_TEST_H

#define RVMODEL_DATA_SECTION                                            \
    .pushsection .tohost, "aw", @progbits;                              \
    .align 8; .global tohost; tohost: .dword 0;                         \
    .align 8; .global fromhost; fromhost: .dword 0;                     \
    .popsection;

#define RVMODEL_BOOT

#define RVMODEL_HALT                                                    \
    li      x1, 1;                                                      \
write_tohost:                                                           \
    sw      x1, tohost, t5;                                             \
    j       write_tohost;

#define RVMODEL_DATA_BEGIN                                              \
    RVMODEL_DATA_SECTION                                                \
    .align 4;                                                           \
    .global begin_signature; begin_signature:

#define RVMODEL_DATA_END                                                \
    .align 4;                                                           \
    .global end_signature; end_signature:

#define RVMODEL_IO_INIT
#define RVMODEL_IO_WRITE_STR(_R, _STR)
#define RVMODEL_IO_CHECK()
#define RVMODEL_IO_ASSERT_GPR_EQ(_S, _R, _I)
#define RVMODEL_IO_ASSERT_SFPR_EQ(_F, _R, _I)
#define RVMODEL_IO_ASSERT_DFPR_EQ(_D, _R, _I)

/* Only the external interrupt exists, and the tests here don't use it */
#define RVMODEL_SET_MSW_INT
#define RVMODEL_CLR_MSW_INT
#define RVMODEL_CLR_MTIMER_INT
#define RVMODEL_CLR_MEXT_INT

#endif
