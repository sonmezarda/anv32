    .section .text.init
    .globl _start
    .type _start, @function

#define CSR_MSTATUS 0x300
#define CSR_MTVEC   0x305
#define CSR_MCAUSE  0x342

#define CSR_INSN(csr, rs1, f3, rd) \
    .word (((csr) << 20) | ((rs1) << 15) | ((f3) << 12) | ((rd) << 7) | 0x73)

#define CSRRW(rd, csr, rs1)  CSR_INSN(csr, rs1, 0x1, rd)
#define CSRRS(rd, csr, rs1)  CSR_INSN(csr, rs1, 0x2, rd)
#define CSRRC(rd, csr, rs1)  CSR_INSN(csr, rs1, 0x3, rd)
#define CSRRWI(rd, csr, imm) CSR_INSN(csr, imm, 0x5, rd)
#define CSRRSI(rd, csr, imm) CSR_INSN(csr, imm, 0x6, rd)
#define CSRRCI(rd, csr, imm) CSR_INSN(csr, imm, 0x7, rd)
#define CSRR(rd, csr)        CSRRS(rd, csr, 0)

_start:
    # x31 is the result marker: 0 means running, 0x7d means pass.
    addi  x31, zero, 0

    # CSRRW: write mtvec from x5, then immediately read it back.
    # This also exercises CSR write -> following CSR read forwarding.
    lui   x5, 0x12345
    CSRRW(0, CSR_MTVEC, 5)
    CSRR(6, CSR_MTVEC)
    bne   x6, x5, fail_1

    # CSRRW returns the old CSR value in rd.
    lui   x7, 0x23456
    CSRRW(8, CSR_MTVEC, 7)
    bne   x8, x5, fail_2
    CSRR(9, CSR_MTVEC)
    bne   x9, x7, fail_3

    # CSRRS with rs1=x0 must be read-only.
    CSRR(10, CSR_MTVEC)
    bne   x10, x7, fail_4

    # CSRRS/CSRRC on mcause. Avoid mstatus here: real RISC-V has WARL fields,
    # while the current core models CSRs as plain registers.
    CSRRW(0, CSR_MCAUSE, 0)
    addi  x11, zero, 8
    CSRRS(12, CSR_MCAUSE, 11)
    bne   x12, zero, fail_5
    CSRR(13, CSR_MCAUSE)
    bne   x13, x11, fail_6
    CSRRC(14, CSR_MCAUSE, 11)
    bne   x14, x11, fail_7
    CSRR(15, CSR_MCAUSE)
    bne   x15, zero, fail_8

    # Immediate CSR ops on mcause.
    CSRRWI(0, CSR_MCAUSE, 5)
    CSRR(16, CSR_MCAUSE)
    addi  x17, zero, 5
    bne   x16, x17, fail_9

    CSRRSI(0, CSR_MCAUSE, 2)   # 5 | 2 = 7
    CSRR(18, CSR_MCAUSE)
    addi  x19, zero, 7
    bne   x18, x19, fail_10

    CSRRCI(20, CSR_MCAUSE, 1)  # old=7, new=6
    bne   x20, x19, fail_11
    CSRR(21, CSR_MCAUSE)
    addi  x22, zero, 6
    bne   x21, x22, fail_12

    # CSRRSI/CSRRCI with zimm=0 must not write.
    CSRRSI(23, CSR_MCAUSE, 0)
    bne   x23, x22, fail_13
    CSRRCI(24, CSR_MCAUSE, 0)
    bne   x24, x22, fail_14
    CSRR(25, CSR_MCAUSE)
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
