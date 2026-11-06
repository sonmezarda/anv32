# anv32im2: where the cycles and the nanoseconds go

*November 2026. anv32im2 before the changes at `1d5cd50`, after them at
`9d4072c`. A follow-up to [the CV32E40P comparison](cv32e40p_comparison.md),
using the same corebench and fpga-eval flows plus the anv32 core probes and
three what-if timing runs.*

anv32im2 was built for Fmax, but it needed 27% more cycles than anv32im1 on
CoreMark, and on the Tang Nano 9K it was no faster than the simpler core,
so it delivered less work per second. This report breaks both sides down,
Fmax and CPI, and estimates what each candidate change would gain. Three of
them were then implemented, C1 and A1 and C2 as an option, and
[Results](#results) compares the measurements with the estimates.

## Results

C1 and A1 are now part of anv32im2, and C2 is the `MUL_PIPE` parameter of
`anv32im2_top` and `anv32_soc_top` (default 0). `make check`, riscv-tests
and riscv-arch-test pass with both multiplier settings. The data is in
[`data/anv32im2_improvements/`](data/anv32im2_improvements/) (before) and
[`data/cv32e40p_comparison/`](data/cv32e40p_comparison/) (after).

| | CoreMark/MHz | Tang Nano 9K Fmax | CoreMark/s | PYNQ-Z2 Fmax | CoreMark/s |
| --- | ---: | ---: | ---: | ---: | ---: |
| anv32im2 before | 1.908 | 26.02 | 49.6 | 80.53 | 153.6 |
| anv32im2 with C1 + A1 | 2.083 | 35.45 | 73.8 | 83.54 | 174.0 |
| ... and `MUL_PIPE=1` | 2.043 | **37.38** | **76.4** | **91.42** | **186.8** |
| anv32im1 | 2.420 | 26.51 | 64.2 | 63.78 | 154.3 |
| CV32E40P (rv32im) | 2.441 | 23.17 | 56.5 | 73.02 | 178.2 |

Fmax is the best of six runs on Gowin and three on Vivado
(`make fpga-eval FPGA_EVAL_VARIANTS=all`).

- **Tang Nano 9K:** +36% Fmax and +49% CoreMark per second. anv32im2 is
  now the fastest core on the board: 15% ahead of anv32im1, which led
  before, and 31% ahead of CV32E40P.
- **PYNQ-Z2:** +4% Fmax and +13% CoreMark per second by default. With
  `MUL_PIPE=1`, +14% Fmax and +22% CoreMark per second, ahead of CV32E40P
  with 60% of its LUTs (2972 against 4940).
- **Area went down:** 4692 → 4452 LUT4 + ALU and 1498 → 1466 registers on
  the GW1NR-9, 3080 → 2972 LUTs on the Zynq-7020. `MUL_PIPE` adds 65
  registers on Gowin and 34 on Vivado.
- **The SoC now meets the board's clock.** The full SoC with anv32im2 at its
  default parameters reaches 26.51 MHz on the GW1NR-9 before the changes,
  short of the board's 27 MHz clock, and 27.03 MHz after (both against a
  27 MHz constraint).

### Estimates against measurements

The estimates were made on the code before the changes, each Fmax from a
single run with the default variant (placement option 0 on Gowin, the
Default directive on Vivado). The middle column uses the same variant.

| | Estimated | Measured, default variant | Measured, best variant |
| --- | ---: | ---: | ---: |
| A1: CoreMark cycles | 4,794,432 | 4,800,931 (+0.14%) | |
| A1: load-use stall cycles | 482,931 | 482,931 | |
| C1: Tang Nano 9K Fmax | 35.34 | 33.60 alone, 32.54 with A1 | 36.55 alone, 35.45 with A1 |
| C1 + C2: PYNQ-Z2 Fmax | 83.19 | 91.42 with A1 | 91.42 with A1 |
| `MUL_PIPE` cycle cost on CoreMark | small | 1.9% | |

The cycle model held. Three things it did not predict:

- **On Vivado, the what-if underestimated.** A false path removes the
  CSR read from timing but leaves its multiplexer in decode, where it still
  shapes placement. C1 deletes it, and the fetch-to-decode path that limited
  the what-if run (83.19 MHz) closes at 91.42 MHz in the real design.
- **A1 does not change Fmax.** A C1-only build reaches 33.6–36.6 MHz over
  the six Gowin variants, and C1 + A1 32.5–35.5 MHz: the same within
  placement noise. A1 only removes a comparison from the D-stage stall
  logic, and the limiting path does not run through it.
- **`MUL_PIPE` costs a cycle per multiply,** not per dependent multiply,
  because the multiply holds E2. CoreMark's ROI has 93,960 multiplies (3% of
  its instructions); the multiply-heavy kernels pay more:

| Cycles (rv32im) | Before | C1 + A1 | `MUL_PIPE=1` | anv32im1 |
| --- | ---: | ---: | ---: | ---: |
| CoreMark | 5,241,746 | 4,800,931 | 4,894,891 | 4,132,303 |
| `crc32` | 5,669 | 5,605 | 5,605 | 5,026 |
| `matrix_mul_4x4` | 1,357 | 1,293 | 1,373 | 1,210 |
| `fir_filter` | 6,109 | 5,781 | 6,109 | 5,081 |
| `memcpy_words` | 9,068 | 8,556 | 8,556 | 7,854 |
| `branchy_state` | 2,884 | 2,788 | 2,788 | 2,494 |

On the GW1NR-9 the `MUL_PIPE=1` build is nevertheless faster in all six runs
(35.8–37.4 MHz), although the multiplier is not on the critical path of
either build there; see [the comparison](cv32e40p_comparison.md#why-the-cores-land-where-they-do).
On the Tang Nano 9K, whose clock is fixed at 27 MHz, the default
`MUL_PIPE=0` is the faster setting because it needs fewer cycles.

### Where the limits are now

| Configuration | Target | Limiting path |
| --- | --- | --- |
| anv32im2 | Tang Nano 9K | E2 operand register → branch compare → redirect → fetch → `D/dinstr_o`, 15 levels |
| anv32im2 | PYNQ-Z2 | E2 operands → multiplier (2 DSP48E1) → E2→E1 forwarding → decode hold (`D/dinstr_o.rs1_rdata`), 11 levels |
| `MUL_PIPE=1` | Tang Nano 9K | E2 operand select → ALU → E2→E1 forwarding → decode hold (`D/dinstr_o.rs2_rdata`), 13 levels |
| `MUL_PIPE=1` | PYNQ-Z2 | fetch BRAM → decode → stall logic → clear of the `D/dinstr_o` registers, 9 levels |

On the Tang Nano 9K, the limits are now the loops the E1/E2 split was built
around: a branch resolved in E2 redirecting fetch, and an ALU result
forwarded into the next instruction's operands in the same cycle. Going
further there takes a different pipeline structure, not another local fix.
In cycles, redirects are now the larger loss: 1,169,585 of the 1,652,516
cycles CoreMark loses (71%), which makes branch handling (B) the next lever,
still without lengthening decode.

### A bug the new test found

A1 makes a consumer pick up a load result in E1 and keep it while E1 is
held, so it came with a directed test,
[`sw/tests/load_use.S`](../../sw/tests/load_use.S): load results used one to
three instructions later as every kind of operand, including behind a
divide or multiply that holds E2. Its wait-state runs failed on the code
before A1, on anv32im1 as well as anv32im2, for a different reason: a
multiply or divide that stalled E wrote a bubble into the E/M register on
every stall cycle, and that register is also what M puts on the data bus.
A load or store still waiting for `mem_ready` when a divide entered E was
dropped. Doom with data wait states found the same bug independently, and
`c0043a3` fixed it by writing the bubble only once M is no longer waiting.
The measurements here were taken with an equivalent fix that also checked
the core's external stall input, which every build here ties low; the
corebench cycle counts are the same with `c0043a3`.

## Proposals at a glance

These are the estimates made before implementation.

| Change | Where | CoreMark/MHz | Tang Nano 9K Fmax | PYNQ-Z2 Fmax |
| --- | --- | ---: | ---: | ---: |
| Before (default variant) | | 1.908 | 25.32 MHz | 78.42 MHz |
| **C1** CSR read out of decode | D → E1 | – | **35.34 (+39.6%)** | no gain alone (multiplier limits) |
| **C2** pipelined multiplier | E2 | – | – (not critical) | 81.77 (+4.3%) |
| C1 + C2 | | – | 35.34 | **83.19 (+6.1%)** |
| **A1** load consumer waits in E1, not D | D stall check | **2.086 (+9.3%)** | expected unchanged | expected unchanged |
| A2 load-use penalty as on anv32im1 | E2 forwarding | 2.215 (+16.1%) | likely lower | likely lower |
| B1 + B2 `jal` and static branch prediction in D | D | 2.076 (+8.8%) | likely lower | likely lower |

Fmax figures come from runs with the path in question removed from timing;
CPI figures are first-order estimates from probe counts (see
[Method](#method)). "Expected unchanged" means the change only touches
stall logic and reuses a path that is already in the netlist.

Recommended order at the time:

1. **C1, moving the CSR read out of decode.** It is the Fmax limit on the
   GW1NR-9 by a wide margin and one of the two limits on 7-series. It is
   self-contained and does not change CPI.
2. **A1, letting a load's consumer wait in E1.** Load-use stalls are the
   largest single cost on CoreMark, and A1 recovers about 60% of the
   load-use difference to anv32im1. The forwarding path it needs already
   exists, so the change is in the stall logic; the work is in proving it
   correct across stalls.
3. **C2, a pipelined multiplier**, once C1 is done and only for 7-series
   targets.
4. **B (branch prediction)** later, and not in decode: decode is the next
   timing limit on both targets once C1 and C2 are in.

With C1 and A1 together, the estimate was 73.7 CoreMark iterations/s on the
Tang Nano 9K (48.3 before, both from single default runs), and the best
measured run gives 73.8.

## Method

- **Cycles.** `make corebench` with the anv32 probes
  ([`sim/corebench/probes/`](../../sim/corebench/probes/)), which count
  redirects, branch outcomes by direction, load-use stalls and, on
  anv32im2, load-use stall episodes by load-to-consumer distance. All
  numbers are for the 10-iteration CoreMark ROI with the rv32im `-O2`
  binary. Saved results before the changes:
  [`data/anv32im2_improvements/before_corebench_results.json`](data/anv32im2_improvements/before_corebench_results.json),
  `probe` fields.
- **CPI estimates.** Each estimate takes the measured event counts and
  changes only the penalty of the events a proposal affects. Interactions
  are ignored: a stall that would overlap with a redirect is counted in
  full. The load-use model matches the measured stall cycles to 0.14%
  (930,245 modeled, 928,921 measured).
- **Fmax what-ifs.** The `make fpga-eval` flow for anv32im2 with its
  default variant, with paths made false: `set_false_path -to` the decode
  CSR read registers (`D/dinstr_o.csr_rdata*`) for C1, and
  `set_false_path -through` every DSP48E1 for C2 (the exact lines are under
  [Reproducing](#reproducing)). A real implementation changes the netlist
  around the path, so these are estimates, not bounds (see
  [Results](#estimates-against-measurements)). Each is a single run:
  [`whatif_fpga_eval.json`](data/anv32im2_improvements/whatif_fpga_eval.json).

## Where the cycles go

On CoreMark, both cores retire the same 3,148,415 instructions; anv32im2
needed 1,109,443 more cycles before the changes:

| | anv32im1 | anv32im2 | Difference |
| --- | ---: | ---: | ---: |
| Cycles | 4,132,303 | 5,241,746 | +1,109,443 |
| Lost cycles (cycles − instructions) | 983,888 | 2,093,331 | |
| Load-use stall cycles | 203,282 | 928,921 | **+725,639 (65%)** |
| Redirect cycles (390,302 redirects) | 780,606 (2.0 each) | 1,164,410 (3.0 each) | +383,804 (35%) |

There are no multiply/divide stalls in the CoreMark ROI on either core: the
multiplier is single-cycle and CoreMark does not divide.

### Load-use stalls

anv32im2 can forward a load result only once the load reaches W, because the
data arrives from block RAM in the cycle after M. Before A1, an instruction
that read a load result waited in D for as long as the load was in E1, E2
or M:

| Distance from the load | Stall episodes | Cycles each | Stall cycles |
| --- | ---: | ---: | ---: |
| Next instruction | 203,282 | 3 | 609,846 |
| Two behind | 76,367 | 2 | 152,734 |
| Three behind | 167,665 | 1 | 167,665 |

anv32im1 forwards from W into E, so only the next instruction stalls, for
one cycle (203,282 cycles). On anv32im2 the same program spent 4.6 times as
much, and the instructions two and three behind a load, which never stall on
anv32im1, added another 320,399 cycles.

### Redirects

| | Count | Share |
| --- | ---: | ---: |
| Conditional branches | 582,985 | 55.8% taken |
| ... backward (loops) | 354,055 | 80.7% taken |
| ... forward | 228,930 | 17.3% taken |
| `jal` | 28,602 | always taken |
| `jalr` | 36,413 | always taken |

Every taken branch or jump costs 3 cycles on anv32im2 (resolved in E2) and
2 on anv32im1 (resolved in E). The direction split is the usual one: loops
branch backward and are taken, error and special-case checks branch forward
and are not. Static backward-taken, forward-not-taken (BTFN) prediction
would be right for 81.5% of conditional branches.

## Where the nanoseconds go

Before the changes, from single runs with the default variant:

| Step | Tang Nano 9K | Limiting path | PYNQ-Z2 | Limiting path |
| --- | ---: | --- | ---: | --- |
| As built | 25.32 | fetch output → decoder CSR address → CSR match → `D/dinstr_o.csr_rdata`, 17 levels | 78.42 | E2 operands → multiplier (2 DSP48E1) → E2→E1 forwarding → decode hold, 14 levels |
| Without the multiplier | – | | 81.77 | fetch BRAM → decode → stall logic → `D/dinstr_o.csr_rdata`, 11 levels |
| Without the CSR read | 35.34 | E2 operand register → branch compare → redirect → fetch → `D/dinstr_o`, 14 levels | – | |
| Without both | – | | 83.19 | fetch BRAM → decode → stall logic → clear of the `D/dinstr_o` registers, 10 levels |

Two conclusions:

- **The CSR read in decode was the common limit.** On Gowin it was the
  worst path by a wide margin: the fetch output, now behind the
  instruction port's skid-buffer multiplexer, the decoder and the CSR read
  multiplexer all fell in one cycle. On 7-series it sat right behind the
  multiplier, so pipelining the multiplier alone gained only 4%.
- **Decode stays the bottleneck.** After C1, the next paths are the E2
  branch redirect into fetch and the D registers on Gowin and the
  decode-to-flush logic on 7-series. Anything that adds logic to decode,
  such as branch prediction there, competes with these paths.

## Proposals

### C1: read CSRs in E1 instead of D

**Before.** D decoded the CSR address from the fetched word, compared it
against every implemented CSR and registered the read data in
`dinstr_o.csr_rdata`. The fetch output, the decoder and the CSR read
multiplexer all fell in one cycle.

**Change.** E1 already picked the CSR value for the instruction it holds
(`csr_e1_rdata` in `anv32im2_top.sv`): the value of an older CSR write still
in M or W, or else `dinstr.csr_rdata`, read in D. C1 replaces that last
source with a CSR file read in E1, using the address that travels with the
instruction anyway; the bypass logic stays as it is. What needed checking
was the ordering against an older CSR write that is still in E2 while the
read happens in E1 (it is in M when the read reaches E2, where
`csr_e2_fwd_comb` already forwards it), the counter read interlock
(`csr_cnt_stall`) and the `mstatus`/`mie` serialization.

**Expected.** About +40% Fmax on the GW1NR-9 (35.34 MHz), no CPI change.
On 7-series it is a precondition for C2.

### C2: pipeline the multiplier (7-series)

**Before.** `anv32_mul_comb` computed the full 64-bit product
combinationally in E2 and forwarded it to E1 in the same cycle. A DSP48E1
multiplies 25×18, so Vivado cascades two DSPs and a CARRY4 chain. The Gowin
MULT36X36 does the same in one block, which is why this path never shows up
on Gowin.

**Change.** Register the product and mark multiplier results as not ready
for forwarding in their first cycle, through the same `e2_fwd_ready` signal
the forwarding unit already checks for results E2 cannot forward yet. A
multiply then holds E2 for a second cycle.

**Expected.** Together with C1, +6% Fmax on the Zynq-7020 (83.19 MHz);
alone, +4% (81.77 MHz). A parameter keeps the single-cycle multiplier as
the default.

### A1: let a load's consumer wait in E1

**Before.** The consumer had to leave D with all operands, and a load result
was only available from W, which gave the 3/2/1-cycle stalls above.

**Change.** Let the consumer advance into E1 while the load is in M. One
cycle later the load is in W, and E1's operand multiplexer
(`select_e1_operand` in `anv32_forward_unit_im2.sv`) already forwards W
results into `rs1_e2_rdata_q`/`rs2_e2_rdata_q`, loads included. The stall
check in D then only has to wait for loads in E1 and E2: the `einstr`
(M-stage) load term goes away.

**Expected.** Each load-use episode gets one cycle shorter: 447,314 cycles
fewer on CoreMark, from 1.908 to 2.086 CoreMark/MHz (+9.3%). The path from
the data BRAM through the load alignment into the E1 operand registers is
already in the netlist and timed, so Fmax should not change. The risk is
correctness: if E1 stalls (for example behind a divide in E2) while the
load retires from W, the consumer must not lose the forwarded value.
Decode's hold path keeps it, and `load_use.S` covers the case.

**A2**, forwarding the load data into the E2 inputs instead (the anv32im1
arrangement), would save 726,963 cycles (+16.1%), but puts the block RAM
output in front of the E2 ALU. anv32im2 was split from anv32im1 to keep
exactly that kind of path short, so A2 is not recommended.

### B: earlier redirects for jumps and branches

Estimated on the code before C1 and A1:

| Option | Cycles saved | CoreMark/MHz |
| --- | ---: | ---: |
| B1: `jal` redirected from D (1 cycle instead of 3) | 57,204 | 1.929 (+1.1%) |
| B2: BTFN prediction in D (predicted taken: 1 cycle, mispredicted: 3) | 366,810 | 2.051 (+7.5%) |
| B1 + B2 | 424,014 | 2.076 (+8.8%) |

The cycles saved do not depend on A1, so on the current code B1 + B2 would
take CoreMark from 2.083 to about 2.29 CoreMark/MHz. B2 also needs a
"predicted taken" bit carried to E2, which then redirects to `pc + 4` when a
predicted-taken branch is not taken. The gain is real, but decode and the
redirect into fetch are where both FPGA targets are limited now, and both
B1 and B2 add an adder and a redirect multiplexer driven from decode.
Better places to look:

- **Predecode in fetch.** Mark backward branches and `jal` and compute their
  targets from the fetched word one stage early, with registered outputs.
- **A small branch target buffer in fetch.** It needs no decoded
  instruction at all and also covers `jalr` returns.

Either is a larger project than C1 and A1, and a natural step toward the
superscalar core on the [roadmap](../roadmap.md).

## Other findings

- **The instruction-port handshake cost anv32im2 12% on Gowin.** The
  valid/ready handshake on the instruction port (`d0f9299`) puts a
  skid-buffer multiplexer between the fetch BRAM and decode. With the CSR
  read in decode, that path was already the limit, and anv32im2's
  default-variant Fmax on the GW1NR-9 went from 28.83 MHz before the
  handshake to 25.32 MHz after it. C1 takes the CSR read off that path,
  which is part of why it gains so much.
- **anv32im1 versus anv32im2 on Gowin.** Before these changes anv32im1 gave
  29% more CoreMark per second on the Tang Nano 9K (64.2 against 49.6), so
  the SoC's default core was not the fastest one on its own board. With C1
  and A1, anv32im2 leads (73.8).
- **Placement noise on Gowin.** The six Gowin variants of one netlist span
  up to 12% in Fmax (anv32im1: 23.7–26.5 MHz). Single runs, as used for the
  what-ifs here, are good enough to find a path but not to rank two close
  configurations.
- **Divider.** CV32E40P's divider finishes in 3 to 35 cycles depending on
  the operands, anv32's always takes 32. CoreMark has no division in its
  timed loop, so this does not show in the numbers above. It matters for
  division-heavy code; skipping iterations from a leading-zero count is a
  contained change.
- **Compressed instructions.** On CV32E40P the C extension cuts CoreMark's
  code by 22.5% for about 2% more cycles, and costs about 720 LUT4 in the
  fetch path. With 32 KiB of block RAM and FreeRTOS, code size matters, but
  so does the GW1NR-9's logic budget. This is a product decision more than
  a performance one.
- **Benchmark coverage.** corebench measures CoreMark and five small
  kernels with zero-wait-state memory. Before deciding on B, Embench-IoT
  would show whether the CoreMark branch mix is typical. A wait-state
  option in the testbench would show how anv32's fetch stage, which has no
  prefetch buffer, copes with slower memory.

## Reproducing

After the changes (`9d4072c`):

```sh
make corebench COREBENCH_CORES=anv32im1,anv32im2,anv32im2_mulpipe COREBENCH_BENCHMARKS=coremark
make fpga-eval FPGA_EVAL_CORES=anv32im2,anv32im2_mulpipe FPGA_EVAL_VARIANTS=all \
               GOWIN_SH=<gw_sh> VIVADO=<vivado>
make check && make riscv-tests arch-test TEST_CORES=anv32im2 MUL_PIPE=1
```

`anv32im2_mulpipe` is the corebench and fpga-eval name for anv32im2 with
`MUL_PIPE=1`. The probe counts are in `build/corebench/results.json`.

Before the changes, check out `1d5cd50` and run the same corebench and
fpga-eval commands for anv32im2; the C1-only numbers come from `7d0d3fc`.
For the Fmax what-ifs, add these constraints at `1d5cd50` and run
`make fpga-eval FPGA_EVAL_CORES=anv32im2` again. Gowin, in
`fpga/eval/constraints/tangnano9k.sdc`:

```tcl
set_false_path -to [get_regs {u_core/u_core_0/D/dinstr_o.csr_rdata*}]
```

Vivado, in `fpga/eval/vivado_eval.tcl` between `synth_design` and
`opt_design` (the cells only exist after synthesis):

```tcl
set_false_path -to [get_cells -hier -filter {NAME =~ *D/dinstr_o_reg[csr_rdata]*}]
set_false_path -through [get_cells -hier -filter {REF_NAME == DSP48E1}]
```

The SoC figures come from the Gowin project in `fpga/gowin/anv32` at
`2022078` (before) and `9d4072c` (after), with the 27 MHz constraint in
`src/anv32.sdc`.
