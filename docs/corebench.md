# corebench: cross-core benchmarks and FPGA evaluation

corebench compares RISC-V cores, ours and other open-source ones, on equal
terms. Every core runs the same binaries in the same testbench, and is
placed and routed in the same FPGA wrapper. Two numbers come out of it:

- **cycles** for a workload, from simulation (`make corebench`)
- **Fmax and utilization** on real FPGA targets (`make fpga-eval`)

Performance at Fmax is the product of the two. The first comparison made
with it is in [`reports/cv32e40p_comparison.md`](reports/cv32e40p_comparison.md).

`make bench` ([`benchmarks.md`](benchmarks.md)) remains the tool for tuning
the anv32 pipelines: it reads anv32 internals to break cycles down into
stall causes, which corebench cannot do for an arbitrary core.

## Quick start

```sh
git submodule update --init third_party/coremark third_party/cv32e40p

make corebench                      # all cores, all benchmarks, native ISA
make corebench COREBENCH_CORES=anv32im2,cv32e40p COREBENCH_ISA=rv32im
make corebench COREBENCH_BENCHMARKS=coremark

make fpga-eval GOWIN_SH=/path/to/gw_sh VIVADO=/path/to/vivado
make fpga-eval FPGA_EVAL_VARIANTS=all ...   # every placement variant, best one kept
make corebench                      # now also reports performance at Fmax
```

`make corebench` reads `build/fpga_eval/summary.json` whenever it exists and
adds per-target columns: CoreMark iterations per second for CoreMark, ROI
run time in microseconds for the other programs.

From WSL, point the variables at the Windows tools directly; paths are
converted with `wslpath`:

```sh
make fpga-eval GOWIN_SH=/mnt/d/Gowin/Gowin_V1.9.11.03_Education_x64/IDE/bin/gw_sh.exe \
               VIVADO=/mnt/d/xilinx/2026.1/Vivado/bin/vivado.bat
```

## Layout

| Path | Contents |
| --- | --- |
| `sim/corebench/cores.json` | Core registry: ISA, RTL sources, adapter, include directories, Verilator flags |
| `sim/corebench/adapters/` | One `corebench_core` adapter per core |
| `sim/corebench/probes/` | Optional `corebench_probe` per core: stall and branch counters |
| `sim/corebench/tb_corebench.sv` | Testbench: RAM, sim-control block, counters |
| `sw/corebench/benchmarks.json` | Benchmark manifest |
| `sw/corebench/common/` | `crt0.S`, linker script, `corebench.h`, minimal libc |
| `sw/corebench/coremark/` | CoreMark port layer (the CoreMark sources stay untouched in `third_party/coremark`) |
| `fpga/eval/` | FPGA wrapper `core_eval_top.sv`, `targets.json`, board constraints, Gowin and Vivado Tcl flows |
| `tools/run_corebench.py` | Builds programs and Verilator models, runs and checks the simulations |
| `tools/fpga_eval.py` | Runs the vendor flows and collects Fmax and utilization |

Outputs go to `build/corebench/` (`results.{json,csv,md}`, plus per-run
`console.log` and `sim.log`) and `build/fpga_eval/` (`summary.json`, plus the
vendor reports in `<target>/<core>/<variant>/`).

## The adapter contract

Each core is wrapped in a module named `corebench_core`, one file per core.
The build picks the file listed for that core in `cores.json`, so the
testbench and the FPGA wrapper never change when a core is added.

```systemverilog
module corebench_core (
    input  logic        clk_i,
    input  logic        rst_ni,         // asynchronous assert, synchronous release
    input  logic        irq_i,          // machine external interrupt, level

    output logic        instr_req_o,
    output logic [31:0] instr_addr_o,
    input  logic [31:0] instr_rdata_i,  // word at last cycle's instr_addr_o

    output logic        data_req_o,
    output logic        data_we_o,
    output logic [ 3:0] data_be_o,      // byte lanes of data_wdata_o
    output logic [31:0] data_addr_o,
    output logic [31:0] data_wdata_o,
    input  logic [31:0] data_rdata_i,   // word at last cycle's data_addr_o

    output logic        retire_o        // one instruction retired (simulation only)
);
```

Both ports behave like a synchronous block RAM with no wait states: a
request is accepted in the cycle it is presented, and read data is valid in
the next cycle. This is what the anv32 cores see on the FPGA. A core with a
handshake bus maps onto it in a few lines; the CV32E40P adapter, for
example, grants every OBI request and raises `rvalid` one cycle later.

`retire_o` must pulse once per retired instruction, using the same event the
core uses to increment `minstret`. It is usually an internal signal, so
adapters drive it through a hierarchical reference under
`` `ifdef COREBENCH_SIM `` and tie it to 0 otherwise; the FPGA flows do not
define that macro.

## The testbench

`tb_corebench.sv` holds a 64 KiB RAM at address 0 and a sim-control block
at `0x2000_0000`:

| Offset | Access | Function |
| --- | --- | --- |
| `0x00` | W | End the run; the value is the exit code |
| `0x04` | W | Write one byte to the console |
| `0x08` | W | Nonzero opens the region of interest (ROI), zero closes it |
| `0x0C` | W | Trap: `mcause`, ends the run (written by the `crt0.S` trap handler) |
| `0x10`, `0x14` | R | Cycle counter, low and high word |
| `0x18`, `0x1C` | R | Retired instruction counter, low and high word |
| `0x20` | W | Trap: `mepc`, written before `0x0C` |

The testbench counts cycles and retired instructions, in total and inside
the ROI. Until a program first writes the ROI register, the whole run is
the ROI; that first write restarts the ROI counts, and from then on only
the open regions count. The ROI may be opened and closed several times. A
store or load outside RAM and the control block stops the simulation with
an error; a fetch outside RAM reads 0, since prefetching cores may fetch
past the end of a program.

Programs only use the control block, never core-specific CSRs. The cycle
counter register lets software such as CoreMark read the time on cores that
lack `mcycle`.

Runtime options are plusargs, so one Verilator model per core runs every
program: `+image=<word hex>`, `+max_cycles=<n>` and `+console=<file>`.

## Core probes

A probe explains where a core loses cycles, which the core-agnostic numbers
cannot. It is an optional module named `corebench_probe`, one file per core
under `sim/corebench/probes/`, listed as `probe` in `cores.json`. The
testbench instantiates it when the model is built with `COREBENCH_PROBE`,
which the runner does whenever a core has one. The probe reads the core's
internal signals through hierarchical references (`tb_corebench.dut.u_core.…`),
counts inside the ROI (`tb_corebench.roi_open`), resets its counts on the
`tb_corebench.roi_restart` event, and prints one line at the end:

```text
COREBENCH_PROBE redirects=390302 branches=582985 load_use_stall_cycles=928921 ...
```

The runner stores the fields under `probe` in `results.json` (`probe.*`
columns in the CSV) and prints a summary table. Sample on the falling clock
edge, where every signal has settled for the cycle the testbench counts at
the next rising edge.

The anv32 probes count redirects, jumps (and how many are `jalr`),
conditional branches by direction and outcome, retired loads, load-use
stall cycles and multiply/divide stall cycles. On anv32im2, which forwards
a load result from W into E1, `load_use_d1` and `load_use_d2` split the
load-use stalls by how far behind the load the consuming instruction is, and
`raw_other` counts stalls that wait on anything else (a divide result).

## Checks

A run passes when:

- the program exits through the control block (not a trap or the timeout)
  with the expected exit code (`expect_exit`, default 0)
- for CoreMark, the program output has no `ERROR` line except the
  "must execute for at least 10 secs" notice, and the run printed its
  results with the expected iteration count. CoreMark checks its own list,
  matrix and state CRCs against the reference values and prints an `ERROR`
  line when they differ.

After the runs, the runner compares the ROI instruction counts of every
program image across the cores that ran it. The same binary must retire the
same number of instructions everywhere; a difference of more than 16 (cores
count retirement at different pipeline stages relative to the ROI marker
stores) is reported as a warning and fails the run. This catches an adapter
whose `retire_o` is wrong.

## Metrics

| Column | Meaning |
| --- | --- |
| `code B` | `.text` + read-only data of the image (`size` "text") |
| `ROI cycles`, `ROI instret` | Cycles and retired instructions inside the ROI |
| `CPI` | ROI cycles / ROI instret |
| `score/MHz` | For benchmarks with a `metric`: iterations × 10⁶ / ROI cycles (CoreMark/MHz for CoreMark) |
| `MHz@target` | Fmax of the core on that FPGA target, from `fpga-eval` |
| `score/us@target` | score/MHz × Fmax for scored benchmarks, otherwise ROI cycles / Fmax in µs |

### About CoreMark numbers

The CoreMark timed section is also the ROI, so the harness counts the same
cycles CoreMark itself measures. The port reports ticks as cycles of a
nominal 1 MHz clock, so CoreMark's own `Iterations/Sec` line reads as
CoreMark/MHz.

The default is 10 iterations of the standard 2 KB performance run
(`PERFORMANCE_RUN`, seeds 0, 0, 0x66). EEMBC rules require at least 10
seconds of run time for a reportable score, which a simulation does not
reach. CoreMark prints that notice and the runner accepts it, but the
numbers here are **simulated CoreMark/MHz**, not certified scores. They are
deterministic and comparable with each other, and per-MHz results converge
within one iteration.

## Adding a core

1. Add the RTL, usually as a submodule under `third_party/`.
2. Write `sim/corebench/adapters/corebench_<core>.sv` with the module and
   ports above. Tie boot address and trap vector to 0, connect `irq_i` to
   the machine external interrupt, and drive `retire_o` from the core's
   `minstret` increment.
3. Add an entry to `sim/corebench/cores.json`:

   ```json
   "mycore": {
     "description": "One line: pipeline, configuration",
     "isa": "rv32imc",
     "upstream": "https://github.com/...",
     "adapter": "sim/corebench/adapters/corebench_mycore.sv",
     "probe": "sim/corebench/probes/corebench_probe_mycore.sv",
     "sources": ["third_party/mycore/rtl/pkg.sv", "..."],
     "include_dirs": ["third_party/mycore/rtl/include"],
     "verilator_flags": []
   }
   ```

   `isa` is the widest ISA the core runs; with `--isa rv32im` it also runs
   the common rv32im binaries. `sources` lists packages first, in
   compilation order. Technology cells such as clock gates need an
   FPGA-safe replacement in `sim/corebench/adapters/`, listed among the
   sources (see `cv32e40p_clock_gate.sv`).
   `probe` is optional (see [Core probes](#core-probes)).
4. Run `make corebench COREBENCH_CORES=mycore,anv32im2 COREBENCH_ISA=rv32im`.
   The instret cross-check against anv32im2 validates the adapter.
5. Run `make fpga-eval FPGA_EVAL_CORES=mycore`.

## Adding a benchmark

Add an entry to `sw/corebench/benchmarks.json`:

```json
"mybench": {
  "description": "What it exercises",
  "sources": ["sw/corebench/mybench/mybench.c"],
  "include_dirs": [],
  "defines": {"SIZE": "256"},
  "expect_exit": 0,
  "max_cycles": 10000000,
  "tags": ["kernel", "memory"]
}
```

`main()`'s return value is the exit code. Wrap the timed part in
`corebench_roi_begin()` / `corebench_roi_end()` from `corebench.h`, so
start-up and result checking stay outside the measurement. For a benchmark
with a score, add `"iterations"`, `"iterations_define"` (the macro that
receives the count) and `"metric"`.

The programs run on the bare core: no libc beyond `memcpy`/`memset`, no
floating point unless every target core has F, and at most 64 KiB for code,
data and an 8 KiB stack.

## Adding an FPGA target

Add an entry to `fpga/eval/targets.json` with the tool (`gowin` or `vivado`),
the device, and constraint files for the `core_eval_top` ports `clk_i`,
`rst_n_i`, `irq_i` and `led_o[3:0]`. Constrain the clock tighter than any
core can meet: Gowin reports Fmax directly, and the Vivado flow derives it
from the routed worst slack (`1000 / (period - WNS)`).

`variants` lists implementation variants as Tcl that the flow evaluates
before implementation: six combinations of Gowin's placement and routing
algorithms (`-place_option 0..1` and `-route_option 0..2`; `-place_option
2` places the GW1NR-9 like 1) and three Vivado `place_design` directives. `make fpga-eval` runs only the first one of each target;
`FPGA_EVAL_VARIANTS=all` runs every variant (or name a list) and
`summary.json` keeps the best run per core and target, with the Fmax of
each variant in its `variants` field.

## Limits

- Memory has no wait states, which favors cores whose fetch unit relies on
  a fast memory. Real systems with caches or flash behave differently.
- By default, Fmax comes from one place-and-route run per core and target.
  On the GW1NR-9 the placement alone moves it by up to 12%, so compare
  cores there with `FPGA_EVAL_VARIANTS=all`.
- Adapters observe retirement through hierarchical references, which only
  Verilator builds use.
