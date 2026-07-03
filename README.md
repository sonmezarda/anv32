# anv32

`anv32` is a learning-focused RV32 microcontroller project written in
SystemVerilog. The project is intentionally iterative: start with a small RV32I
core, add ISA features, react to timing pressure with new pipeline revisions,
then grow the SoC and peripheral subsystem in a more realistic direction.

The repository currently contains three in-order RISC-V cores, a Gowin FPGA SoC,
Verilator-based tests, a bare-metal software flow, working UART and I2C
peripherals, and early infrastructure for a ready/valid-style data bus.

## Current Status

- `anv32i1`: first RV32I + `Zicsr` core with basic trap/interrupt support.
- `anv32im1`: RV32IM + `Zicsr`, adding multiply/divide to the earlier pipeline.
- `anv32im2`: newer RV32IM + `Zicsr` pipeline revision focused on timing and
  cleaner multi-cycle behavior.
- FPGA SoC is running on Tang Nano 9K / Gowin.
- UART TX/RX, programmable baud generation, and FIFO-backed UART integration are
  working.
- I2C master is working with real hardware: a 2x16 I2C LCD text test and a
  QMC5883L magnetometer register read/write smoke test have both run on FPGA.
- The core data-memory path now has `mem_valid_o` / `mem_ready_i`, and a
  cycle-level trace test verifies that the pipeline stalls while memory is not
  ready.
- A shared peripheral bus/interconnect is the next architectural step; MMIO is
  still decoded directly in the SoC top today.

## Core Family

| Core | ISA | Notes |
| --- | --- | --- |
| `anv32i1` | RV32I + `Zicsr` | First simple core revision |
| `anv32im1` | RV32IM + `Zicsr` | Adds `M` extension support |
| `anv32im2` | RV32IM + `Zicsr` | Newer timing-oriented pipeline revision |

The naming scheme is:

- `i`, `im`: ISA level
- trailing number: microarchitecture revision

## Architecture Snapshot

- ISA coverage: `RV32I`, `RV32IM`, `Zicsr`
- Privilege level: machine mode only
- Memory organization: separate instruction and data ports, with a unified
  address map at the SoC level
- On-chip memory: synchronous BRAM with byte-lane init files
- External interrupt path: simple GPIO-backed pending/clear mechanism
- Data memory handshake: `mem_valid_o`, `mem_ready_i`, `mem_rdata_i`,
  `mem_wdata_o`, `mem_addr_o`, `mem_we`
- Current peripheral integration: direct MMIO decode
- Planned peripheral integration: small reusable valid/ready bus and slave
  wrappers for UART, I2C, GPIO, timer, SPI, and memory

## SoC Top Levels

The shared SoC implementation is [`rtl/soc/anv32_soc_top.sv`](rtl/soc/anv32_soc_top.sv).
It selects the core with `CORE_TYPE`:

| `CORE_TYPE` | Core |
| --- | --- |
| `0` | `anv32i1` |
| `1` | `anv32im1` |
| `2` | `anv32im2` |

Compatibility wrappers are provided:

- [`anv32i1_soc_top`](rtl/soc/anv32i1_soc_top.sv)
- [`anv32im1_soc_top`](rtl/soc/anv32im1_soc_top.sv)
- [`anv32im2_soc_top`](rtl/soc/anv32im2_soc_top.sv)

The Gowin FPGA project currently targets the `anv32im2` SoC wrapper.

## MMIO Map

Current FPGA MMIO map:

| Address | Function |
| --- | --- |
| `0x1000_0000` | Debug LEDs |
| `0x1000_0010` | GPIO IRQ pending / clear |
| `0x1000_1000` | UART TX data |
| `0x1000_1004` | UART status |
| `0x1000_1008` | UART baud rate |
| `0x1000_100C` | UART error flags / clear |
| `0x1000_2000` | I2C command |
| `0x1000_2004` | I2C status |
| `0x1000_2008` | I2C RX data |
| `0x1000_200C` | I2C control |

MMIO accesses are gated with `mem_valid`, and writes commit only when
`mem_ready` is high. In the current SoC, `mem_ready` is tied high, but the core
and tests already support wait states.

## UART

UART RTL lives under [`rtl/peripherals/uart/core`](rtl/peripherals/uart/core).

Implemented pieces:

- `uart_tx.sv`: byte serializer with ready/done-style control
- `uart_rx.sv`: receiver with oversampling and majority voting
- `uart_baud_rate.sv`: programmable baud-rate tick generator
- `uart_fifo.sv`: synchronous FIFO
- `uart_top.sv`: TX/RX/FIFO integration wrapper

The FPGA UART hello program is [`sw/fpga/uart_hello.c`](sw/fpga/uart_hello.c).

## I2C

I2C RTL lives under [`rtl/peripherals/i2c`](rtl/peripherals/i2c).

Implemented pieces:

- `i2c_byte_master_timed.sv`: timed byte engine with START, repeated START,
  transmit, receive, ACK/NACK, STOP, clock stretching wait, timeout, and basic
  transmit arbitration-lost detection.
- `i2c_cmd_master_timed.sv`: command engine with command FIFO, RX FIFO, bus
  busy/free check, bus recovery, and sticky error bits.
- `i2c_periph.sv`: current MMIO wrapper exposing `CMD`, `STATUS`, `RXDATA`, and
  `CTRL`.

The FPGA QMC5883L smoke test is [`sw/fpga/i2c_qmc5883l.c`](sw/fpga/i2c_qmc5883l.c).
It queues byte-level I2C commands from software and prints magnetometer `XYZ`
samples over UART.

## Data Memory Ready/Valid Work

The core data path now exposes a memory handshake:

```text
mem_valid_o
mem_ready_i
mem_addr_o
mem_wdata_o
mem_we
mem_rdata_i
```

When `mem_valid_o` is high and `mem_ready_i` is low, the pipeline holds the
memory request stable and stalls the relevant stages. This is the foundation for
the upcoming peripheral bus, slow register blocks, synchronous peripheral reads,
and external-memory style wait states.

The dedicated trace test is:

```sh
make mem-ready-trace CYCLES=100 MEM_READY_WAIT=3
```

The test injects wait states into memory accesses and checks that address, write
data, and byte enables remain stable while all pipeline stages stall.

## Repository Layout

- `rtl/`: RTL sources
- `rtl/core/`: core pipelines and shared core blocks
- `rtl/peripherals/`: UART, I2C, and placeholder directories for GPIO/SPI/timer
- `rtl/soc/`: FPGA SoC wrappers and shared SoC top
- `sim/`: Verilator testbenches
- `sw/`: bare-metal examples, FPGA test programs, and benchmark sources
- `fpga/gowin/`: Gowin project and generated FPGA images
- `tools/`: host-side build and conversion scripts
- `docs/`: notes, roadmap, benchmark notes, and simulation docs

## Requirements

For simulation and software builds:

- `verilator`
- `python3`
- `riscv64-unknown-elf-gcc`
- `riscv64-unknown-elf-objcopy`
- `riscv64-unknown-elf-objdump`

Optional for golden-reference flows:

- `spike`

## Simulation and Software Flow

Common RTL tests:

```sh
make de
make m
make fetch_top
make all
make list
```

Build a C program and verify the generated instruction image through the fetch
path:

```sh
make sw-fetch
make sw-fetch C_SRC=sw/examples/smoke.c SW_NAME=smoke
make sw-fetch KEEP=asm,hex,lanes,dump
```

Run the CPU trace flow:

```sh
make cpu-run C=sw/examples/smoke.c CYCLES=80
make cpu-run ASM=sw/examples/load_timing.S CYCLES=80 DETAIL=1
```

Run the memory-ready stall trace:

```sh
make mem-ready-trace CYCLES=100 MEM_READY_WAIT=3
```

Assembly vs Spike diff flow:

```sh
make asm-diff-test ASM=sw/examples/hazard_raw.S
```

Benchmark flow:

```sh
make bench
make bench BENCHMARKS=balanced BENCH_CORES=anv32im2
make bench BENCH_FMAX='anv32i1=27,anv32im1=27,anv32im2=33'
```

More detail is available in [`docs/simulation.md`](docs/simulation.md).

## FPGA Flow

The active FPGA project is under [`fpga/gowin/anv32`](fpga/gowin/anv32).

Build a C program for FPGA BRAM init:

```sh
make fpga FILE=sw/fpga/led.c
make fpga FILE=sw/fpga/uart_hello.c
make fpga FILE=sw/fpga/i2c_qmc5883l.c
```

Equivalent explicit targets:

```sh
make fpga-c C=sw/fpga/uart_hello.c
make fpga-c C=sw/fpga/i2c_qmc5883l.c
make fpga-asm ASM=sw/fpga/led.S
```

These update:

- `fpga/gowin/anv32/src/prog.hex`
- `fpga/gowin/anv32/src/prog_lane0.hex`
- `fpga/gowin/anv32/src/prog_lane1.hex`
- `fpga/gowin/anv32/src/prog_lane2.hex`
- `fpga/gowin/anv32/src/prog_lane3.hex`

The Gowin project references RTL directly from `rtl/`, so there is no duplicated
RTL tree inside the FPGA project.

## What Works Today

- RV32I execution on the first core revision
- RV32IM execution on `anv32im1` and `anv32im2`
- CSR instructions needed by the current machine-mode flow
- Basic trap and external interrupt plumbing
- BRAM-backed instruction/data memory model
- Data-memory wait-state support in the core pipeline
- GPIO-backed IRQ pending latch in the SoC
- UART serial output on FPGA
- I2C LCD bring-up on FPGA
- I2C QMC5883L register read/write and live `XYZ` output over UART
- Verilator unit tests, CPU traces, Spike diff tests, and synthetic benchmarks

## Known Gaps

- No shared peripheral bus/interconnect yet
- MMIO is still direct address decode in the SoC top
- I2C timing and timeout values are currently RTL parameters, not runtime MMIO
  registers
- UART RX exists in the reusable block, but the current FPGA software examples
  mainly exercise UART TX
- No full debug module
- Privilege support is machine mode only
- RISC-V compliance-level corner cases are still incomplete

## Near-Term Direction

The next stage is SoC-focused:

- introduce a small valid/ready peripheral bus
- move BRAM, UART, I2C, GPIO, timer, and SPI behind bus slave wrappers
- add `bus_error` handling and connect it to load/store access-fault traps
- make I2C timing/IRQ/status behavior more MCU-like
- add SPI after the bus shape is stable

## Notes

- Some documents in `docs/` are still written in Turkish and may lag behind the
  latest RTL.
- This README is intended to describe the current codebase rather than the full
  long-term goal.
