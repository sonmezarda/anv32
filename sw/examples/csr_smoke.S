    .section .text.init
    .globl _start
    .type _start, @function

_start:
    # x31 is the result marker: 0 means running, 0x7d means pass.
    addi  x31, zero, 0

    # CSRRW: write mtvec from x5, then immediately read it back.
    # This also exercises CSR write -> following CSR read forwarding.
    lui   x5, 0x12345
    csrw  mtvec, x5
    csrr  x6, mtvec
    bne   x6, x5, fail_1

    # CSRRW returns the old CSR value in rd.
    lui   x7, 0x23456
    csrrw x8, mtvec, x7
    bne   x8, x5, fail_2
    csrr  x9, mtvec
    bne   x9, x7, fail_3

    # CSRRS with rs1=x0 must be read-only.
    csrr  x10, mtvec
    bne   x10, x7, fail_4

    # CSRRS/CSRRC on mcause. Avoid mstatus here: real RISC-V has WARL fields,
    # while the current core models CSRs as plain registers.
    csrw  mcause, zero
    addi  x11, zero, 8
    csrrs x12, mcause, x11
    bne   x12, zero, fail_5
    csrr  x13, mcause
    bne   x13, x11, fail_6
    csrrc x14, mcause, x11
    bne   x14, x11, fail_7
    csrr  x15, mcause
    bne   x15, zero, fail_8

    # Immediate CSR ops on mcause.
    csrwi mcause, 5
    csrr  x16, mcause
    addi  x17, zero, 5
    bne   x16, x17, fail_9

    csrsi mcause, 2             # 5 | 2 = 7
    csrr  x18, mcause
    addi  x19, zero, 7
    bne   x18, x19, fail_10

    csrrci x20, mcause, 1       # old=7, new=6
    bne   x20, x19, fail_11
    csrr  x21, mcause
    addi  x22, zero, 6
    bne   x21, x22, fail_12

    # CSRRSI/CSRRCI with zimm=0 must not write.
    csrrsi x23, mcause, 0
    bne   x23, x22, fail_13
    csrrci x24, mcause, 0
    bne   x24, x22, fail_14
    csrr  x25, mcause
    bne   x25, x22, fail_15

pass:
    addi  x31, zero, 0x7d
    ebreak

fail_1:  addi x31, zero, 1;  ebreak
fail_2:  addi x31, zero, 2;  ebreak
fail_3:  addi x31, zero, 3;  ebreak
fail_4:  addi x31, zero, 4;  ebreak
fail_5:  addi x31, zero, 5;  ebreak
fail_6:  addi x31, zero, 6;  ebreak
fail_7:  addi x31, zero, 7;  ebreak
fail_8:  addi x31, zero, 8;  ebreak
fail_9:  addi x31, zero, 9;  ebreak
fail_10: addi x31, zero, 10; ebreak
fail_11: addi x31, zero, 11; ebreak
fail_12: addi x31, zero, 12; ebreak
fail_13: addi x31, zero, 13; ebreak
fail_14: addi x31, zero, 14; ebreak
fail_15: addi x31, zero, 15; ebreak
