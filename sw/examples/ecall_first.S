    .section .text.init
    .globl _start
    .type _start, @function

#define CSR_MTVEC   0x305
#define CSR_MEPC    0x341
#define CSR_MCAUSE  0x342

#define CSR_INSN(csr, rs1, f3, rd) \
    .word (((csr) << 20) | ((rs1) << 15) | ((f3) << 12) | ((rd) << 7) | 0x73)

#define CSRRW(rd, csr, rs1) CSR_INSN(csr, rs1, 0x1, rd)
#define CSRRS(rd, csr, rs1) CSR_INSN(csr, rs1, 0x2, rd)
#define CSRR(rd, csr)       CSRRS(rd, csr, 0)
#define MRET                .word 0x30200073

_start:
    addi  x31, zero, 0

    lui   x5, %hi(trap_handler)
    addi  x5, x5, %lo(trap_handler)
    CSRRW(0, CSR_MTVEC, 5)

ecall_site:
    ecall

after_ecall:
    addi  x31, zero, 0x7d
    ebreak

trap_handler:
    CSRR(6, CSR_MCAUSE)
    addi  x7, zero, 11
    bne   x6, x7, fail_mcause

    CSRR(28, CSR_MEPC)
    lui   x29, %hi(ecall_site)
    addi  x29, x29, %lo(ecall_site)
    bne   x28, x29, fail_mepc

    addi  x28, x28, 4
    CSRRW(0, CSR_MEPC, 28)
    MRET

fail_mcause:
    addi  x31, zero, 1
    ebreak

fail_mepc:
    addi  x31, zero, 2
    ebreak
