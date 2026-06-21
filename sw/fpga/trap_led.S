    .section .text.init
    .globl _start
    .type _start, @function

#define LED_BASE    0x10000
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
    lui   s1, LED_BASE       # LED MMIO base: 0x1000_0000
    addi  s0, zero, 0        # trap flags: bit0=ecall, bit1=illegal

    lui   t0, %hi(trap_handler)
    addi  t0, t0, %lo(trap_handler)
    CSRRW(0, CSR_MTVEC, 5)

    ecall
    addi  t0, zero, 1
    bne   s0, t0, fail_ecall

illegal_site:
    .word 0xffffffff

    addi  t0, zero, 3
    bne   s0, t0, fail_illegal

pass_loop:
    addi  t0, zero, 0x0a
    sw    t0, 0(s1)
    jal   ra, delay
    addi  t0, zero, 0x05
    sw    t0, 0(s1)
    jal   ra, delay
    jal   zero, pass_loop

fail_ecall:
    addi  t0, zero, 0x01
    jal   zero, fail_loop

fail_illegal:
    addi  t0, zero, 0x02
    jal   zero, fail_loop

fail_unknown:
    addi  t0, zero, 0x0e

fail_loop:
    sw    t0, 0(s1)
    jal   zero, fail_loop

trap_handler:
    CSRR(5, CSR_MCAUSE)

    addi  t1, zero, 11
    beq   t0, t1, handle_ecall

    addi  t1, zero, 2
    beq   t0, t1, handle_illegal

    jal   zero, fail_unknown

handle_ecall:
    ori   s0, s0, 1
    jal   zero, trap_resume

handle_illegal:
    ori   s0, s0, 2

trap_resume:
    CSRR(7, CSR_MEPC)
    addi  t2, t2, 4
    CSRRW(0, CSR_MEPC, 7)
    MRET

delay:
    lui   t2, 0x800
1:
    addi  t2, t2, -1
    bne   t2, zero, 1b
    jalr  zero, 0(ra)
