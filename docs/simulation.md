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
make bus          # bus decoder, bridge and register aliases
make icache       # instruction cache, several geometries
make list         # list registered tests
```

`make icache` runs `anv32_icache` with five geometries at once (both tag modes,
32- and 64-bit line fills, 4 to 16 beats per line). A core model issues fetches
that follow the bus protocol and a memory model answers line fills with random
delays; every word, every line request and the hit latency are checked, and
memory is changed and the cache invalidated now and then.

`make WARN=1 <test>` shows Verilator lint warnings, and `EXTRA_VFLAGS="..."`
passes extra flags to Verilator.

## Core, SoC and FreeRTOS tests

```sh
make core-tests
make core-tests TEST_CORES=anv32im2 TEST_NAMES=irq_sweep,muldiv
make core-tests TEST_SUITES=soc
make core-tests TEST_SUITES=rtos
make check        # unit tests + core/SoC/FreeRTOS tests + bootloader + riscv-tests + benchmarks
```

`tools/run_core_tests.py` builds each test program once and each testbench once
per core, then prints a pass/fail table. It exits non-zero if any test fails.

**Core suite** ([`sw/tests/tests.json`](../sw/tests/tests.json)): self-checking
assembly programs run on the bare core by `sim/tb/common/tb_core_test.sv`. A
small test device in the testbench lets a program report pass/fail and raise
the external interrupt a given number of cycles later (see
[`sw/tests/test.h`](../sw/tests/test.h)). The interrupt tests sweep that delay
so the interrupt hits every pipeline position. Every test also runs a second
time with random wait states on the instruction and data ports. The testbench
also checks the bus protocol on both ports: a request that is not accepted
yet must not change.

| Test           | Covers |
| -------------- | ------ |
| `trap_ecall`   | ECALL trap CSRs, mstatus MIE/MPIE/MPP, ECALL right after enabling MIE |
| `trap_illegal` | illegal instruction traps and `mtval`, `FENCE` as a no-op |
| `csr_rw`       | CSR instruction semantics, CSR reads one to three instructions after a write |
| `mem_access`   | load/store widths, sign extension, store/load and load/store pairs |
| `irq_basic`    | MIE/MEIE masking, interrupt taken right after it is enabled |
| `irq_sweep`    | interrupts at every point of a loop with load-use and jumps |
| `irq_critical` | no interrupt inside a critical section, no starvation of a short window |
| `muldiv`       | RV32M results and corner cases, dependent multi-cycle chains |
| `load_use`     | load results used one to three instructions later, kept across a divide or multiply stall |
| `irq_div`      | interrupts while the divider is busy |
| `div_mem_stall` | a divide entering E while the load/store ahead of it waits on the data bus |

**SoC suite** ([`sw/tests/soc/tests.json`](../sw/tests/soc/tests.json)): C
programs run on `anv32_soc_top` by `sim/tb/soc/tb_soc_test.sv`. Results come
back through the LED register; the UART TX pin is looped back to RX.

| Test                | Covers |
| ------------------- | ------ |
| `soc_regs`          | register reset values and read-back (UART, I2C, NN, SYSCTRL) |
| `soc_alias`         | SET/CLR/XOR register aliases, including byte and halfword stores |
| `soc_unmapped`      | unmapped addresses ignore writes, read zero, leave RAM alone |
| `soc_uart_loopback` | UART TX/RX through the FIFOs |
| `soc_gpio_irq`      | GPIO interrupt pending/clear and the external interrupt path |
| `soc_clint`         | `mtime` rate, timer and software interrupts through a C handler (im1/im2) |
| `soc_nn_smoke`      | one small dense layer on the NN accelerator |

**FreeRTOS suite** ([`sw/freertos/tests.json`](../sw/freertos/tests.json)):
FreeRTOS programs on the same testbench, built with 32 KiB of BRAM
(`BRAM_ADDR_W=13`) and no NN accelerator, as in the default FPGA build. The kernel is the `third_party/FreeRTOS-Kernel` submodule
(`git submodule update --init`), using the official RISC-V port unchanged with
the CLINT tick; the board files are in [`sw/freertos`](../sw/freertos).
Runs on im1 and im2.

| Test            | Covers |
| --------------- | ------ |
| `freertos_demo` | tick timing against `mtime`, a queue with both sides blocking, an `msip` interrupt waking a task through a semaphore, and two register test tasks time-sliced by the tick that check every register survives a context switch |

To add a test, put the source next to the others and add an entry to the
matching `tests.json` (`"requires": ["m"]` for programs that need the M
extension).

## Bootloader test

```sh
make boot-test
```

`tools/run_boot_test.py` runs `sim/tb/soc/tb_soc_boot.sv` on every core, on
the default SoC with the bootloader merged into the BRAM image as `make fpga`
does it. The testbench plays the host on the UART pins and checks that a
power-on runs the program at 0 at once and that its stores to the bootloader
were dropped, that the trigger resets into the bootloader (after near misses),
that a bad CRC and a bad length are refused, and that a good image runs.

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
also runs with random instruction- and data-port wait states.

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

## Doom on the simulation platform

```sh
python3 tools/run_doom_sim.py --core anv32im1 --video build/doom/doom.mp4
python3 tools/run_doom_sim.py --core anv32im2 --max-frames 300 --png 100,250
```

Runs [doomgeneric](https://github.com/ozkl/doomgeneric) on
`sim/tb/common/tb_platform.sv`: one core with 32 MiB of RAM at `0x8000_0000`
(where external RAM sits in the SoC memory map) and a small device for
console output, exit and frame dumps. The port in [`sw/doom`](../sw/doom)
draws into an 8-bit indexed 320x200 buffer and hands each frame and the
palette to the testbench; the shareware IWAD is linked into the image and
served through a minimal POSIX layer on top of picolibc. There is no input,
so the game runs its attract mode: title screen, then demo playback.

The script fetches doomgeneric at a pinned commit, uses the system picolibc
(`picolibc-riscv64-unknown-elf`) or extracts the Debian package locally
without installing it, and does the same for the shareware WAD
(`doom-wad-shareware`) unless `--wad` points at one. Nothing from these ends
up in the repository; everything goes under `build/`. Frames are converted
by `tools/doom_frames.py` (needs Pillow, and ffmpeg for `--video`).

Game time comes from `rdcycle` with an assumed 50 MHz clock, so the frame
rate in the dump is what the core would reach at that clock with
single-cycle memory. The simulation runs at about 3 million cycles per
second; the first frame appears after about 300 million cycles.

`--imem-lat N` and `--dmem-lat N` make every instruction fetch or RAM
load/store wait N cycles before it is accepted, which is roughly what a core
without caches would see on external memory. `--lat-from-frame K` turns the
wait states on only after K frames, so the start-up still runs at full speed,
and `--window N` stops after N instructions with the wait states on and
prints the cycles, CPI and wait cycles of that window:

```sh
python3 tools/run_doom_sim.py --core anv32im1 --imem-lat 20 --dmem-lat 20 \
    --lat-from-frame 1 --window 20000000
```

`--icache-size N` puts `anv32_icache` in front of the instruction port
(`--icache-line`, `--icache-mem-dw` and `--icache-sync-tags` set the rest). Line
fills then come from a burst memory: the first beat `--imem-lat` cycles after
the request, then one beat per cycle. Each cache configuration gets its own
simulator build.

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
