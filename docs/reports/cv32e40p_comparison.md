# anv32 and CV32E40P on Gowin and AMD FPGAs

*November 2026. anv32 at `9d4072c`, CV32E40P at `b353438`, CoreMark at
`1f483d5`.*

This report compares the anv32 cores with OpenHW's
[CV32E40P](https://github.com/openhwgroup/cv32e40p), a mature open-source
RV32IMC core, on two FPGA targets: the Gowin GW1NR-9C on the Tang Nano 9K
(the anv32 development board) and the AMD Zynq-7020 programmable logic on the
PYNQ-Z2. Each core was evaluated on its own (core plus 8 KiB of block RAM)
for maximum clock frequency and utilization, and simulated cycle-accurately
on CoreMark and five C kernels. Section [Reproducing](#reproducing) lists
the commands; the raw results are in
[`data/cv32e40p_comparison/`](data/cv32e40p_comparison/).

anv32im2 appears twice: as built by default, and with `MUL_PIPE=1`, which
registers the multiplier output. How anv32im2 got here from its earlier
state is in [`anv32im2_improvements.md`](anv32im2_improvements.md).

## Summary

| | anv32i1 | anv32im1 | anv32im2 | anv32im2 `MUL_PIPE=1` | CV32E40P |
| --- | ---: | ---: | ---: | ---: | ---: |
| CoreMark/MHz (rv32im binary) | 0.93¹ | 2.42 | 2.08 | 2.04 | **2.44** |
| Tang Nano 9K: Fmax (MHz) | 25.2 | 26.5 | 35.5 | **37.4** | 23.2 |
| Tang Nano 9K: LUT4 + ALU | 3501 | 4365 | 4452 | 4554 | 8240 (95%) |
| Tang Nano 9K: CoreMark iterations/s | 23.3 | 64.2 | 73.8 | **76.4** | 56.5 |
| PYNQ-Z2: Fmax (MHz) | 71.9 | 63.8 | 83.5 | **91.4** | 73.0 |
| PYNQ-Z2: LUT6 | 2308 | 3446 | 2972 | 2972 | 4940 |
| PYNQ-Z2: CoreMark iterations/s | 66.6 | 154.3 | 174.0 | **186.8** | 178.2 |

¹ anv32i1 has no M extension and runs an rv32i build of CoreMark.

Fmax is the best of several place-and-route runs per core and target (six
on Gowin, three on Vivado; see [FPGA flow](#fpga-flow)).

- **Per cycle, CV32E40P and anv32im1 are equal** (2.44 and 2.42
  CoreMark/MHz, CPI 1.30 and 1.31 on the same binary). anv32im2 gives up
  15% of that for its extra pipeline stage.
- **CV32E40P needs 1.85× (Gowin) and 1.66× (Vivado) the logic of
  anv32im2.** Most of the difference is its register file, which no FPGA RAM
  can hold: 2686 of the 3788 extra LUT4 on Gowin, and on Vivado the register
  file alone is larger than the whole difference (see
  [Area](#why-cv32e40p-is-larger)). On the GW1NR-9 the core fills 95% of the
  device, which leaves no room for the rest of an SoC.
- **On the Gowin part, anv32im2 is the fastest core.** Its Fmax is 53%
  above CV32E40P's, and it delivers 31% more CoreMark per second than
  CV32E40P and 15% more than anv32im1, with 54% of CV32E40P's logic.
- **On 7-series, anv32im2 with `MUL_PIPE=1` is the fastest core.** It
  delivers 5% more CoreMark per second than CV32E40P with 60% of its LUTs.
  Without `MUL_PIPE`, anv32im2 is 2% behind CV32E40P there.
- **anv32's register file costs almost nothing**: 2 block RAMs on Gowin, 44
  LUTs of distributed RAM on Vivado. On CV32E40P the same structure takes
  992 flip-flops and about 2600 LUTs.

## Setup

### Cores

| | anv32i1 | anv32im1 | anv32im2 | CV32E40P |
| --- | --- | --- | --- | --- |
| ISA | RV32I | RV32IM | RV32IM | RV32IMC |
| Pipeline | 5 stages | 5 stages | 6 stages (E1/E2) | 4 stages (IF ID EX WB) |
| Register file | 1 write port, BRAM/LUTRAM | same | same | 2 write ports, flip-flops |
| `mul` / `mulh` | – | 1 / 1 cycle | 1 / 1 cycle (2 / 2 with `MUL_PIPE=1`) | 1 / 5 cycles |
| `div` | – | 32 cycles | 32 cycles | 3–35 cycles |
| Taken branch | resolved in E | resolved in E | resolved in E2 | resolved in EX, 3 cycles |

CV32E40P was configured with `COREV_PULP=0`, `COREV_CLUSTER=0`, `FPU=0` and
one HPM counter, and uses `cv32e40p_register_file_ff.sv`. Its debug module
interface and the full CSR set stay in the design, since they cannot be
configured out. Its technology clock gate (`cv32e40p_clock_gate`) is replaced
with a pass-through for both simulation and FPGA: a fabric-gated clock is
unsafe on an FPGA. The core still signals sleep, but its flops keep their
clock.

### FPGA flow

Each core is wrapped in [`fpga/eval/core_eval_top.sv`](../../fpga/eval/core_eval_top.sv):
an 8 KiB true dual-port block RAM (`anv32_bram_tdp`, fetch on one port, data
on the other), a 4-bit LED register written by stores to `addr[31]`, and a
synchronized external interrupt input. There is no bus fabric and there are
no peripherals, so the reported timing is the core's own.

| Target | Device | Tool | Clock constraint | Variants |
| --- | --- | --- | --- | --- |
| `tangnano9k` | GW1NR-LV9QN88PC6/I5 (LUT4) | Gowin EDA 1.9.11.03 Education | 50 MHz | `-place_option` 0, 1 × `-route_option` 0, 1, 2 |
| `pynq_z2` | xc7z020clg400-1 (LUT6) | Vivado 2026.1, non-project flow with `phys_opt_design` | 125 MHz | `place_design -directive` Default, Explore, ExtraTimingOpt |

Both constraints sit above what any core reaches, so place-and-route keeps
optimizing for speed. Gowin reports the achieved Fmax directly; for Vivado
it is `1000 / (period - WNS)` of the routed design. The inputs are
asynchronous and synchronized, and the LED outputs are excluded from timing.

Every core was implemented once per variant, and the tables report the
best run. Placement alone moves Fmax a lot on the GW1NR-9, so a single run
is not enough to rank cores there:

| Fmax over the variants (MHz) | anv32i1 | anv32im1 | anv32im2 | anv32im2 `MUL_PIPE=1` | CV32E40P |
| --- | --- | --- | --- | --- | --- |
| Tang Nano 9K (6 runs) | 23.9–25.2 | 23.7–26.5 | 32.5–35.5 | 35.8–37.4 | 21.5–23.2 |
| PYNQ-Z2 (3 runs) | 71.2–71.9 | 59.5–63.8 | 82.8–83.5 | 88.4–91.4 | 71.2–73.0 |

### Benchmark flow

All cores ran in the same Verilator testbench
([corebench](../corebench.md)), with zero-wait-state memory on both ports,
the timing the core sees from block RAM on the FPGA. Programs were compiled
with GCC 13.2.0 at `-O2`. Every core ran the same rv32im image; CV32E40P
also ran an rv32imc build of the same source, and anv32i1 an rv32i build.

CoreMark is the unmodified EEMBC source with a corebench port layer: 10
iterations of the 2 KB performance run, timed by the testbench over exactly
the section CoreMark times itself. Every run produced the reference CRCs.
These are simulated scores, comparable with each other but not reportable
EEMBC scores, which need at least 10 seconds of run time (see
[About CoreMark numbers](../corebench.md#about-coremark-numbers)).
The five kernels from `sw/benchmarks_c` were timed over the whole program.

Each image retired the same number of instructions on every core (CoreMark:
3,148,415), which confirms that every adapter counts retirement correctly.

## Results

### Fmax and utilization

**Tang Nano 9K** (GW1NR-9C: 8640 LUT4, 6693 registers, 26 BSRAM, 10 DSP)

| Core | Fmax (MHz) | Logic levels | LUT4 + ALU | Registers | BSRAM | DSP |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| anv32i1 | 25.18 | 17 | 3501 (3289 + 212) | 992 | 6 | 0 |
| anv32im1 | 26.51 | 17 | 4365 (4086 + 279) | 1225 | 6 | 2 |
| anv32im2 | 35.45 | 15 | 4452 (4112 + 340) | 1466 | 6 | 2 |
| anv32im2 `MUL_PIPE=1` | **37.38** | 13 | 4554 (4216 + 338) | 1531 | 6 | 2 |
| CV32E40P | 23.17 | 21 | 8240 (7740 + 500) | 2066 | 4 | 3 |

For the anv32 cores, 4 BSRAM are the 8 KiB memory and 2 hold the register
file. For comparison, the full SoC with anv32im2 (UART, I2C, GPIO, CLINT,
bootloader, bus) meets the board's 27 MHz clock on the same device (27.03
MHz achieved).

**PYNQ-Z2** (Zynq-7020 PL: 53,200 LUT6, 106,400 registers, 140 BRAM tiles, 220 DSP48E1)

| Core | Fmax (MHz) | WNS at 8 ns | Logic levels | LUT | of which LUTRAM | Registers | BRAM tiles | DSP48E1 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| anv32i1 | 71.92 | −5.904 | 17 | 2308 | 44 | 997 | 2 | 0 |
| anv32im1 | 63.78 | −7.679 | 19 | 3446 | 44 | 1235 | 2 | 4 |
| anv32im2 | 83.54 | −3.970 | 11 | 2972 | 44 | 1473 | 2 | 4 |
| anv32im2 `MUL_PIPE=1` | **91.42** | −2.938 | 9 | 2972 | 44 | 1507 | 2 | 4 |
| CV32E40P | 73.02 | −5.694 | 14 | 4940 | 0 | 2099 | 2 | 5 |

The 44 LUTRAMs of the anv32 cores are the register file. Utilization is
that of the best run; it varies by about 1% between Vivado directives.

### Cycles

**CoreMark** (10 iterations)

| Core | ISA | Code (bytes) | Cycles | Instructions | CPI | CoreMark/MHz |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| anv32i1 | rv32i | 15,764 | 10,805,103 | 7,574,935 | 1.426 | 0.925 |
| anv32im1 | rv32im | 14,416 | 4,132,303 | 3,148,415 | 1.313 | 2.420 |
| anv32im2 | rv32im | 14,416 | 4,800,931 | 3,148,415 | 1.525 | 2.083 |
| anv32im2 `MUL_PIPE=1` | rv32im | 14,416 | 4,894,891 | 3,148,415 | 1.555 | 2.043 |
| CV32E40P | rv32im | 14,416 | 4,097,323 | 3,148,415 | 1.301 | **2.441** |
| CV32E40P | rv32imc | 11,172 | 4,177,690 | 3,148,415 | 1.327 | 2.394 |

"Code" is `.text` plus read-only data. Published CV32E40P figures range from
2.17 CoreMark/MHz (core-v-verif defaults, [corev-dev mailing
list](https://www.eclipse.org/lists/corev-dev/msg00094.html)) to about 2.7
with the Xpulp extensions and the PULP GCC ([Gallmann et al., CARRV
2021](https://carrv.github.io/2021/papers/CARRV2021_paper_8_Gallmann.pdf)).
The 2.44 measured here, without Xpulp and with upstream GCC 13 at `-O2`, sits
between the two.

**C kernels** (cycles for the whole program; anv32i1 runs rv32i builds)

| Kernel | anv32i1 | anv32im1 | anv32im2 | anv32im2 `MUL_PIPE=1` | CV32E40P rv32im | CV32E40P rv32imc |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `crc32` | 5,026 | 5,026 | 5,605 | 5,605 | 5,031 | 5,031 |
| `matrix_mul_4x4` | 3,625 | 1,210 | 1,293 | 1,373 | 1,199 | 1,199 |
| `fir_filter` | 43,112 | 5,081 | 5,781 | 6,109 | 5,045 | 5,045 |
| `memcpy_words` | 7,854 | 7,854 | 8,556 | 8,556 | 7,731 | 8,235 |
| `branchy_state` | 2,494 | 2,494 | 2,788 | 2,788 | 2,470 | 2,470 |

The kernels are short (1,000–6,500 instructions in the rv32im builds) and
include start-up, but they agree with CoreMark: anv32im1 and the rv32im
build on CV32E40P are within 2% of each other everywhere, and anv32im2
needs 7–14% more cycles than anv32im1 (16% on CoreMark).

### Performance at Fmax

| Core | ISA | Tang Nano 9K iterations/s | per 1000 LUT4 + ALU | PYNQ-Z2 iterations/s | per 1000 LUT6 |
| --- | --- | ---: | ---: | ---: | ---: |
| anv32i1 | rv32i | 23.3 | 6.7 | 66.6 | 28.8 |
| anv32im1 | rv32im | 64.2 | 14.7 | 154.3 | 44.8 |
| anv32im2 | rv32im | 73.8 | 16.6 | 174.0 | 58.6 |
| anv32im2 `MUL_PIPE=1` | rv32im | **76.4** | **16.8** | **186.8** | **62.8** |
| CV32E40P | rv32im | 56.5 | 6.9 | 178.2 | 36.1 |
| CV32E40P | rv32imc | 55.5 | 6.7 | 174.8 | 35.4 |

## Analysis

### Why CV32E40P is larger

Per-block utilization from Gowin synthesis (LUT4 + ALU, registers):

| Block | CV32E40P | anv32im2 |
| --- | --- | --- |
| Register file | 2686, **992 regs** | 2 BSRAM |
| Decode, operand registers, forwarding | `id_stage` without register file, decoder and controller: 2230, 238 regs | `D` + `E1` + `fwd_unit` + `hazard_unit`: 1013, 459 regs |
| Fetch | `if_stage` (prefetch buffer, aligner, compressed decoder): 719, 198 regs | `fetch` 137, 131 regs |
| CSRs | `cs_registers` 1025, 460 regs | `csr` 682, 352 regs |
| Divider | `alu_div` 660, 107 regs | `u_div` 489, 139 regs |

**The register file is the largest single difference.** On Vivado it is
2558 LUTs and 992 flip-flops for CV32E40P, against 44 LUTs of distributed
RAM for anv32. FPGA memories, both distributed and block RAM, offer one
write port per address and no reset of their contents. CV32E40P's register
file has neither property:

```systemverilog
// cv32e40p_id_stage.sv: port A takes load results in WB, port B takes ALU,
// multiplier and divider results directly from EX
.waddr_a_i(regfile_waddr_wb_i),     .we_a_i(regfile_we_wb_power_i),
.waddr_b_i(regfile_alu_waddr_fw_i), .we_b_i(regfile_alu_we_fw_power_i)

// cv32e40p_register_file_ff.sv: every word has an asynchronous reset
if (rst_n == 1'b0) mem[i] <= 32'b0;
else if (we_b_dec[i] == 1'b1) mem[i] <= wdata_b_i;
else if (we_a_dec[i] == 1'b1) mem[i] <= wdata_a_i;
```

The second write port is what lets CV32E40P write ALU results from EX and
keep a four-stage pipeline. The design targets ASICs. Its intended register
file is `cv32e40p_register_file_latch.sv`, which stores each bit in a latch
(about half the area of a flip-flop) and opens one word at a time with a
clock gate, so a second write port costs only a small mux per word. On an
FPGA, latches occupy full flip-flop sites and clock gates in fabric are
unsafe, so the flip-flop version is the only usable one. It turns into 992
registers, a 2:1 write mux and enable in front of every one of them, and two
32-to-1 read multiplexers of 32 bits each.

anv32 has one write port and no reset on its register array, which
`anv32_regfile.sv` describes as a plain memory. Gowin maps it to two
semi-dual-port block RAMs (one per read port), and Vivado maps the
asynchronous read onto distributed RAM.

**The rest:**

- The C extension costs about 720 LUT4 in the fetch path: the prefetch FIFO,
  an aligner for 32-bit instructions that straddle words, and the
  compressed decoder. In exchange the code is 22.5% smaller (11,172 against
  14,416 bytes), at a cost of 2% in cycles on CoreMark and 6.5% on
  `memcpy_words`. That matches the extra cycle the CV32E40P manual lists for
  a taken branch to a 32-bit instruction that is not word-aligned, which
  only happens in compressed code.
- The CSR file always includes debug mode (`dcsr`, `dpc`, `dscratch0/1`), the
  trigger module and the performance counter infrastructure.
- The ID stage still carries operand paths sized for the Xpulp instructions
  (a third operand, separate multiplier operand registers) even with
  `COREV_PULP=0`.

### Why the cores land where they do

Critical paths of the best runs:

| Core | Target | Path | Notes |
| --- | --- | --- | --- |
| CV32E40P | Tang Nano 9K | `id_stage/alu_operator_ex_o` → ALU adder → divider operand mux → register file read and forwarding → `mult_operand_a_ex_o` | 21 levels |
| CV32E40P | PYNQ-Z2 | `alu_operand_a_ex_o` → ALU → ID forwarding → `alu_operand_a_ex_o` | 14 LUT levels, 84% routing |
| anv32im2 | Tang Nano 9K | E2 operand register → branch compare → redirect → fetch → `D/dinstr_o` | 15 levels |
| anv32im2 | PYNQ-Z2 | E2 operands → multiplier (2 DSP48E1) → E2→E1 forwarding → decode hold (`D/dinstr_o.rs1_rdata`) | 11 levels, 65% logic |
| anv32im2 `MUL_PIPE=1` | Tang Nano 9K | E2 operand select → ALU → E2→E1 forwarding → decode hold (`D/dinstr_o.rs2_rdata`) | 13 levels |
| anv32im2 `MUL_PIPE=1` | PYNQ-Z2 | fetch BRAM → decode → stall logic → clear of the `D/dinstr_o` registers | 9 levels, 66% routing |
| anv32im1 | Tang Nano 9K | `D/dinstr_o.rs1_idx` → forwarding select → ALU → redirect → `fetch/pc_fetch` | 17 levels |
| anv32im1 | PYNQ-Z2 | data BRAM → load forwarding → multiplier → `E/einstr_o.alu_result` | 19 levels, 11 CARRY4 |
| anv32i1 | Tang Nano 9K | data BRAM → W→E forwarding → ALU → trap → `csr/mcause_q` | 17 levels |
| anv32i1 | PYNQ-Z2 | data BRAM → W→E forwarding → branch compare → redirect → fetch → `D/dinstr_o` | 17 levels, 63% routing |

CV32E40P's limiting path is structural. The EX result is forwarded to the
operand multiplexers in ID and registered into the ID/EX operand registers
in the same cycle, so one cycle covers the ALU, the forwarding mux and the
operand select. The ALU also shares its shifter and leading-zero count with
the divider (`shift_amt = div_valid ? div_shift : operand_b_i` in
`cv32e40p_alu.sv`), which adds a mux level and heavy fan-out to that path.
The five-stage anv32 cores have the same structure, forwarding into E and
then the ALU and the redirect in one cycle, and land close to CV32E40P on
Gowin. anv32im2 breaks the loop with its separate E1 stage: an ALU result
reaches the next instruction's operand registers and nothing behind them,
and branches resolve from registered operands.

The two fabrics weigh these paths differently:

- **Gowin LUT4 at 95% utilization.** Every wide mux costs more levels in LUT4
  than in LUT6, and at 95% the placer cannot keep CV32E40P's forwarding
  logic together. The register file read muxes compete for the same area.
- **7-series LUT6 at 9% utilization.** LUT6 and the F7 muxes make the
  register file and the forwarding muxes shallow, and routing is unconstrained.
  What becomes critical for anv32 is the single-cycle multiplier: a
  DSP48E1 multiplies 25×18, so a 32×32 product cascades two DSPs and a
  CARRY4 chain. Gowin's MULT36X36 does it in one block, which is why the
  multiplier never appears on the Gowin side. CV32E40P computes only the low
  word in one cycle (`mulh` takes five), so its multiplier is shallower and
  its ALU path stays critical. `MUL_PIPE=1` takes the anv32im2 multiplier off
  the forwarding path, which leaves the fetch-to-decode logic as the limit.

On the GW1NR-9 the `MUL_PIPE=1` build is faster in every one of the six
runs (35.8–37.4 MHz against 32.5–35.5) although the multiplier is on
neither build's critical path. The difference comes from placement, and it
is large enough to make up for the build's 1.9% more cycles. On the board,
whose clock is fixed at 27 MHz, `MUL_PIPE=0` is the better choice.

### Why anv32im2 trades CPI for Fmax

anv32im2 resolves branches one stage later than anv32im1, and it forwards a
load result only from W, into E1. The core probes show what that costs on
CoreMark: 16% more cycles than anv32im1 (CPI 1.525 against 1.313), of which
58% are the third cycle of every redirect (390,302 taken branches and
jumps) and 42% are load-use stalls (482,931 stall cycles against 203,282;
the instruction right after a load waits two cycles, the one after it one).

The trade pays off on both targets. anv32im2's Fmax is 34% above
anv32im1's on the GW1NR-9 and 31% above it on the Zynq-7020, which outweighs
the CPI loss on both. CV32E40P shows that a short pipeline with full
forwarding can reach anv32im1's CPI with a better Fmax on 7-series, but it
pays for that in area that the GW1NR-9 does not have.

## Limitations

- **Memory model.** Both ports have zero wait states. This matches the
  block RAM systems both cores were built in, but cores react differently to
  slower memory (CV32E40P's prefetch buffer hides latency better than
  anv32's fetch stage), so the cycle counts do not carry over to systems
  with flash or caches.
- **CoreMark scores.** These are simulated CoreMark/MHz values from 10
  iterations, not EEMBC-reportable scores, which require at least 10
  seconds of run time on hardware. Per-MHz results are deterministic and
  match within 0.1% between 1 and 10 iterations.
- **Few implementation runs.** Each Fmax is the best of six (Gowin) or
  three (Vivado) runs. That narrows the placement noise shown in
  [FPGA flow](#fpga-flow) but does not remove it; on Gowin, treat
  differences under about 10% with care.
- **Over-constrained clocks.** Vivado's Fmax is derived from the worst
  slack at a 125 MHz target. A constraint closer to the achievable frequency
  can change the result by a few percent in either direction.
- **Interrupts.** The interrupt input is connected so its logic is not
  optimized away, but no benchmark takes an interrupt.
- **Block RAM hint.** On Vivado, `anv32_bram_tdp` needed a `ram_style`
  attribute: without it, Vivado mapped the 8 KiB memory to distributed RAM
  for anv32i1 and anv32im1 (2,200 to 2,600 extra LUTs, and a lower Fmax)
  but not for the other cores. All results above use block RAM throughout.

## Next steps

- **anv32im2.** Redirects are now the larger part of the cycles it loses
  to anv32im1 and CV32E40P. [`anv32im2_improvements.md`](anv32im2_improvements.md)
  estimates what branch prediction would recover and where it could go
  without lengthening decode.
- **More reference points.** Ibex, PicoRV32, VexRiscv and SERV cover the
  range from minimal to performance-oriented cores, and each needs only an
  adapter (see [Adding a core](../corebench.md#adding-a-core)). Embench-IoT
  would complement CoreMark with a broader workload mix.

## Reproducing

```sh
git submodule update --init third_party/coremark third_party/cv32e40p

make fpga-eval FPGA_EVAL_VARIANTS=all FPGA_EVAL_JOBS=4 GOWIN_SH=<gw_sh> VIVADO=<vivado>
make corebench COREBENCH_ISA=native,rv32im
```

The FPGA runs take about an hour with four in parallel; corebench takes
about a minute. Tools used: Gowin EDA V1.9.11.03 Education, Vivado 2026.1,
Verilator 5.020, riscv64-unknown-elf-gcc 13.2.0. The results files are
copied in [`data/cv32e40p_comparison/`](data/cv32e40p_comparison/):
`fpga_eval_summary.json` from `build/fpga_eval/summary.json` (best run per
core and target, with every variant's Fmax) and `corebench_results.json`
from `build/corebench/results.json`, including the anv32 probe counts. The
SoC figure comes from the Gowin project in `fpga/gowin/anv32` at its
default parameters.
