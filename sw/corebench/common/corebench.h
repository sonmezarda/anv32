// corebench sim-control block, implemented by sim/corebench/tb_corebench.sv.
// Programs use it for console output, the exit code and region-of-interest
// markers; the testbench counts cycles and retired instructions inside the
// ROI. Usable from C and from assembly (crt0.S).
#ifndef COREBENCH_H
#define COREBENCH_H

#define COREBENCH_CTRL_BASE  0x20000000

#define COREBENCH_EXIT       0x00   // W: end the run with this exit code
#define COREBENCH_PUTC       0x04   // W: console byte
#define COREBENCH_ROI        0x08   // W: nonzero opens, zero closes the ROI
#define COREBENCH_TRAP_CAUSE 0x0C   // W: mcause, ends the run as a trap
#define COREBENCH_CYCLE      0x10   // R: cycle counter [31:0]
#define COREBENCH_CYCLEH     0x14   // R: cycle counter [63:32]
#define COREBENCH_INSTRET    0x18   // R: retired instructions [31:0]
#define COREBENCH_INSTRETH   0x1C   // R: retired instructions [63:32]
#define COREBENCH_TRAP_EPC   0x20   // W: mepc, written before TRAP_CAUSE

#ifndef __ASSEMBLER__

#define COREBENCH_REG(off) (*(volatile unsigned int *)(COREBENCH_CTRL_BASE + (off)))

static inline void corebench_putc(char c) { COREBENCH_REG(COREBENCH_PUTC) = (unsigned char)c; }

static inline void corebench_puts(const char *s)
{
    while (*s)
        corebench_putc(*s++);
}

// The ROI can be opened and closed several times; the counts accumulate.
// Without any markers the whole run counts as the ROI.
static inline void corebench_roi_begin(void) { COREBENCH_REG(COREBENCH_ROI) = 1; }
static inline void corebench_roi_end(void)   { COREBENCH_REG(COREBENCH_ROI) = 0; }

// Testbench cycle counter, available on every core whether or not it
// implements mcycle.
static inline unsigned int corebench_cycles(void) { return COREBENCH_REG(COREBENCH_CYCLE); }

static inline void corebench_exit(int code)
{
    COREBENCH_REG(COREBENCH_EXIT) = (unsigned int)code;
    for (;;)
        ;
}

#endif  // __ASSEMBLER__
#endif  // COREBENCH_H
