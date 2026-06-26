# anv32

`anv32` is a learning-focused RV32 microcontroller project built in SystemVerilog.
The repository currently contains multiple in-order RISC-V cores, a small FPGA SoC,
Verilator-based tests, a bare-metal software flow, and a working UART bring-up on
Gowin FPGA hardware.

The project is intentionally iterative: simple cores come first, then ISA features,
then timing-driven microarchitecture changes, then SoC and peripheral work.

## Current Status

- `anv32i1`: RV32I + `Zicsr`, basic trap/interrupt support.
- `anv32im1`: RV32IM + `Zicsr`, multiply/divide added on top of the simpler core.
- `anv32im2`: RV32IM + `Zicsr`, newer pipeline variant created to relieve timing pressure.
- FPGA SoC for `anv32im2` is up and running on Gowin.
- UART TX/RX, programmable baud generation, and FIFO-backed UART top-level are integrated.
- A simple MMIO UART test program is working on FPGA and prints a message over serial.

## Core Family

| Name | Meaning |
| --- | --- |
| `anv32i1` | First RV32I core |
| `anv32im1` | RV32I core extended with `M` |
| `anv32im2` | Newer RV32IM core revision focused on timing/pipeline changes |

The naming scheme is:

- `i`, `im`: ISA level
- trailing number: microarchitecture revision

## Architecture Snapshot

- ISA: `RV32I`, `RV32IM`, `Zicsr`
- Privilege level: machine mode only
- Memory model: modified Harvard style
  Separate instruction and data ports, unified address space at the SoC level
- On-chip memory: synchronous BRAM
- External interrupt support: simple GPIO-backed external IRQ path exists in the SoC
- Peripheral integration style today: direct MMIO decode in SoC top
- Peripheral bus: not implemented yet


## SoC and MMIO

The active FPGA SoC is [`anv32im2_soc_top`](rtl/soc/anv32im2_soc_top.sv).

Current MMIO map used by the FPGA bring-up:

| Address | Function |
| --- | --- |
| `0x1000_0000` | Debug LEDs |
| `0x1000_0010` | GPIO IRQ pending / clear |
| `0x1000_1000` | UART TX data |
| `0x1000_1004` | UART status |
| `0x1000_1008` | UART baud rate |
| `0x1000_100C` | UART error flags / clear |

UART is currently integrated without a shared peripheral bus. The SoC decodes these
addresses directly and forwards writes/reads to the UART block.

## UART Block

UART RTL lives under [`rtl/peripherals/uart/core`](rtl/peripherals/uart/core).

Implemented pieces:

- `uart_tx.sv`: byte serializer
- `uart_rx.sv`: 16x oversampling receiver with 3-sample majority vote
- `uart_baud_rate.sv`: programmable baud-rate tick generator
- `uart_fifo.sv`: simple synchronous FIFO
- `uart_top.sv`: TX/RX/FIFO integration wrapper

The UART top is deliberately split into:

- protocol core pieces
- a wrapper that looks more like a reusable peripheral building block

That structure is meant to make the later MMIO wrapper / bus integration cleaner.

## Repository Layout

- `rtl/`: RTL sources
- `sim/`: Verilator testbenches
- `sw/`: bare-metal software, examples, FPGA test programs
- `fpga/gowin/`: Gowin project and FPGA images
- `tools/`: host-side build and conversion scripts
- `docs/`: notes and workflow docs

## Requirements

For simulation and software builds:

- `verilator`
- `python3`
- `riscv64-unknown-elf-gcc`
- `riscv64-unknown-elf-objcopy`
- `riscv64-unknown-elf-objdump`

Optional for golden-reference style flows:

- `spike`

## Simulation and Software Flow

The repo includes a small bare-metal flow:

1. C or assembly source
2. compile/link into ELF
3. convert ELF to raw binary
4. convert binary to 32-bit word hex
5. split word hex into 4 byte-lane BRAM init files

Useful commands:

```sh
make de
make m
make fetch_top
make all
make list
```

Build a C program and verify the generated instruction image through the fetch path:

```sh
make sw-fetch
```

Build a custom C program:

```sh
make sw-fetch C_SRC=sw/examples/smoke.c SW_NAME=smoke
```

Keep intermediate files:

```sh
make sw-fetch KEEP=asm,hex,lanes,dump
```

Assembly vs Spike diff flow:

```sh
make asm-diff-test ASM=sw/examples/hazard_raw.S
```

More detail is available in [`docs/simulation.md`](docs/simulation.md).

## FPGA Flow

The active FPGA project is under [`fpga/gowin/anv32`](fpga/gowin/anv32).

Build a C program for FPGA BRAM init:

```sh
make fpga-c FPGA_C_SRC=sw/fpga/led.c
```

Build the current UART hello test:

```sh
make fpga-c FPGA_C_SRC=sw/fpga/uart_hello.c FPGA_C_NAME=uart_hello
```

This updates:

- `fpga/gowin/anv32/src/prog.hex`
- `fpga/gowin/anv32/src/prog_lane0.hex`
- `fpga/gowin/anv32/src/prog_lane1.hex`
- `fpga/gowin/anv32/src/prog_lane2.hex`
- `fpga/gowin/anv32/src/prog_lane3.hex`

The Gowin project references RTL directly from `rtl/`, so there is no duplicated RTL tree
inside the FPGA project.

## What Works Today

- Basic RV32I execution
- CSR instructions needed by the current core flow
- Multiply/divide on `anv32im1` and `anv32im2`
- Trap/interrupt plumbing at a simple machine-mode level
- BRAM-backed instruction/data memory model
- GPIO-backed IRQ pending latch in the SoC
- UART serial output on FPGA using `sw/fpga/uart_hello.c`

## Known Gaps

- No shared peripheral bus yet
- MMIO accesses are still handled by direct address decode
- UART RX is integrated in the reusable block, but the SoC test path is currently TX-focused
- No full debug module
- Privilege support is machine mode only
- Some RISC-V corner cases and compliance-level behavior are still incomplete

## Near-Term Direction

The next stage of the project is more SoC-focused:

- add more peripherals such as GPIO, timer, SPI, I2C
- introduce a small reusable peripheral interconnect
- keep the peripheral cores reusable and separate from MMIO wrappers
- continue comparing simpler and more timing-friendly core variants

## Notes

- Some docs in `docs/` are still written in Turkish and may lag behind the latest RTL.
- This README is meant to reflect the current state of the codebase more closely than older notes.
