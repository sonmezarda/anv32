# Simulation

Everything runs through the top-level `Makefile` and Verilator. `make help`
lists every target and variable.

The default toolchain prefix is `riscv64-unknown-elf-`. If your toolchain uses
different names, override them:

```sh
make cpu-run SW_CC=riscv32-unknown-elf-gcc \
             SW_OBJCOPY=riscv32-unknown-elf-objcopy \
             SW_OBJDUMP=riscv32-unknown-elf-objdump
```

## Unit tests

```sh
make all          # run every registered test
make de           # decode + execute (anv32i1)
make m            # memory stage
make fetch_top    # fetch path through anv32i1_top
make list         # list registered tests
```

`make WARN=1 <test>` shows Verilator lint warnings, and `EXTRA_VFLAGS="..."`
passes extra flags to Verilator.

## Core and SoC tests

```sh
make core-tests
make core-tests TEST_CORES=anv32im2 TEST_NAMES=irq_sweep,muldiv
make core-tests TEST_SUITES=soc
make check        # unit tests + core/SoC tests + riscv-tests + benchmarks
```

`tools/run_core_tests.py` builds each test program once and each testbench once
per core, then prints a pass/fail table. It exits non-zero if any test fails.

**Core suite** ([`sw/tests/tests.json`](../sw/tests/tests.json)): self-checking
assembly programs run on the bare core by `sim/tb/common/tb_core_test.sv`. A
small test device in the testbench lets a program report pass/fail and raise
the external interrupt a given number of cycles later (see
[`sw/tests/test.h`](../sw/tests/test.h)). The interrupt tests sweep that delay
so the interrupt hits every pipeline position. Every test also runs a second
time with random data-port wait states.

| Test           | Covers |
| -------------- | ------ |
| `trap_ecall`   | ECALL trap CSRs, mstatus MIE/MPIE/MPP, ECALL right after enabling MIE |
| `trap_illegal` | illegal instruction traps and `mtval`, `FENCE` as a no-op |
| `csr_rw`       | CSR instruction semantics, back-to-back CSR write/read |
| `mem_access`   | load/store widths, sign extension, store/load and load/store pairs |
| `irq_basic`    | MIE/MEIE masking, interrupt taken right after it is enabled |
| `irq_sweep`    | interrupts at every point of a loop with load-use and jumps |
| `irq_critical` | no interrupt inside a critical section, no starvation of a short window |
| `muldiv`       | RV32M results and corner cases, dependent multi-cycle chains |
| `irq_div`      | interrupts while the divider is busy |

**SoC suite** ([`sw/tests/soc/tests.json`](../sw/tests/soc/tests.json)): C
programs run on `anv32_soc_top` by `sim/tb/soc/tb_soc_test.sv`. Results come
back through the LED register; the UART TX pin is looped back to RX.

| Test                | Covers |
| ------------------- | ------ |
| `soc_regs`          | register reset values and read-back (UART, I2C, NN, SYSCTRL) |
| `soc_unmapped`      | unmapped addresses ignore writes, read zero, leave RAM alone |
| `soc_uart_loopback` | UART TX/RX through the FIFOs |
| `soc_gpio_irq`      | GPIO interrupt pending/clear and the external interrupt path |
| `soc_nn_smoke`      | one small dense layer on the NN accelerator |

To add a test, put the source next to the others and add an entry to the
matching `tests.json` (`"requires": ["m"]` for programs that need the M
extension).

## RISC-V compliance tests

```sh
make riscv-tests                    # riscv-tests: rv32ui, rv32um, rv32mi
make arch-test SPIKE=/path/to/spike # riscv-arch-test: I, M, privilege
```

`tools/run_compliance.py` clones both repositories at pinned versions into
`build/third_party` on first use. The test binaries are linked at
`0x80000000` ([`sw/compliance/link.ld`](../sw/compliance/link.ld)) and the
testbench is built with the same reset PC.

- **riscv-tests** check themselves and write the result to `tohost`.
- **riscv-arch-test** writes a signature to memory. Each test runs on Spike
  and on the core, and the two signatures must match word by word.
  [`sw/compliance/model_test.h`](../sw/compliance/model_test.h) holds the
  model macros for both.

A few tests are skipped because they need features the cores do not have
(Zifencei, misaligned access in hardware, Sdtrig, PMP entries). The runner
prints each skipped test with the reason. As in the core suite, every test
also runs with random data-port wait states.

`make arch-test` needs Spike. The CI workflow builds it from a pinned commit;
see [`.github/workflows/ci.yml`](../.github/workflows/ci.yml).

## Running programs on a core

`cpu-run` builds a C or assembly program, prints the disassembly and runs it
on `anv32im1` with a per-cycle pipeline trace. The run stops at `EBREAK` or
after `CYCLES` cycles.

```sh
make cpu-run C=sw/examples/smoke.c CYCLES=80
make cpu-run ASM=sw/examples/load_timing.S CYCLES=80 DETAIL=1
make cpu-run ASM=prog.S SW_ARCH=rv32im_zicsr      # allow M instructions
```

Options:

| Variable           | Effect                                                  |
| ------------------ | ------------------------------------------------------- |
| `CYCLES=n`         | cycle limit (default 80)                                |
| `DETAIL=1`         | print a detailed block for every cycle                  |
| `TRACE=1`          | write a VCD to `obj_dir/cpu_trace.vcd`                  |
| `PIPELINE_LOG=f`   | write the detailed trace to a file                      |
| `SW_OPT=-O2`       | GCC optimization level for C (default `-Os`)            |
| `SW_ARCH=...`      | `-march` value (default `rv32i_zicsr`)                  |

Build outputs go to `build/sw/<name>/` for C and `build/asm/<name>/` for
assembly.

C programs are linked with `sw/common/crt0.S`. It sets up the stack, calls
`main()`, stores the return value in `_test_result`, then executes `EBREAK`.

## Memory wait states

```sh
make mem-ready-trace CYCLES=100 MEM_READY_WAIT=3
```

Runs `sw/examples/load_timing.S` (or `MEM_READY_ASM=...`) on `anv32im2` with
`mem_ready` held low for `MEM_READY_WAIT` cycles on every data access. It
checks that address, write data and byte enables stay stable while the
pipeline is stalled.

## Spike diff

These targets need `spike` installed. The program is linked at `0x80000000`
and runs on both Spike and the core. The two commit logs (PC, instruction
word and register writes) are then compared.

```sh
make asm-diff-test ASM=sw/examples/hazard_raw.S
make asm-diff-test ASM=sw/examples/hazard_auipc_jalr.S CYCLES=30 SPIKE_INSNS=30
make asm-hard-test     # the RV32I stress programs in sw/examples
```

Logs are written to `build/golden/asm/<name>/`:

```text
spike.raw.log    spike.norm.log    core.norm.log    pipeline.log    commit.diff
```

`make asm-golden-run` produces the logs without running the diff.

## Benchmarks

```sh
make bench
```

See [benchmarks.md](benchmarks.md).

## Program images

The BRAM is split into four byte lanes, so every program image is stored as one
word hex file plus four lane files (`<name>_lane0.hex` ... `<name>_lane3.hex`).
The build scripts generate these automatically:

```text
tools/build_rv32_program.py      C -> ELF -> bin -> word hex -> lane hex
tools/build_rv32_asm_program.py  same flow for assembly
tools/bin_to_hex.py              raw binary -> 32-bit word hex
tools/split_hex.py               word hex -> four lane hex files
```

`make sw-fetch` builds a C program and checks that every instruction word is
read back correctly through the fetch path. This is useful when changing the
image flow. Use `KEEP=asm,hex,lanes,elf,bin,dump,map,obj` (or `KEEP=all`) to
keep intermediate files under `build/sw/<name>/`.

## Cleaning up

```sh
make clean
```

This removes `obj_dir/`, generated lane hex files and `build/sw/`.
