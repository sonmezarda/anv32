# Roadmap

anv32 is still under active development. This page lists what is done and
what comes next.

## Where things stand

- `anv32i1`, `anv32im1` and `anv32im2` pass the unit tests, the core/SoC
  test suites, every benchmark self-check, riscv-tests (rv32ui, rv32um,
  rv32mi) and riscv-arch-test (I, M, privilege) compared against Spike.
  Skipped tests need Zifencei, misaligned access in hardware, Sdtrig or PMP
  entries.
- UART and I2C (16x2 LCD, QMC5883L magnetometer) have been tested on a Tang
  Nano 9K. The MNIST demo drives the NN accelerator from a host over UART.

## anv32i1 is frozen

`anv32i1` is meant to stay a simple RV32I reference core above 27 MHz on the
GW1NR-9. After CSRs, exceptions and the external interrupt were added, it
closed at about 27.07 MHz. Bigger features would break that budget, so they
go into the `im` cores instead.

Out of scope for `anv32i1`: M extension, vectored or multi-source interrupts,
nested interrupts, a debug module, accelerator interfaces.

## Core

- A superscalar core as the next microarchitecture step after `anv32im2`
- A Linux-capable core: S and U modes, Sv32 MMU, the A extension, and the
  timer/interrupt support Linux expects
- `FENCE.I` (Zifencei)
- Zbs (single-bit instructions: `bset`, `bclr`, `binv`, `bext`), and later
  other bit-manipulation extensions (Zba, Zbb)
- Access-fault traps on bus errors
- `mtvec` vectored mode (the CLINT timer and software interrupts are done on
  `anv32im1`/`anv32im2`)
- `time`/`timeh` CSRs (Zicntr `rdtime`) as a shadow of the CLINT `mtime`
- An interrupt controller and general-purpose timers (alarms, PWM, capture)
  that share the CLINT `mtime` as their time base
- Trigger CSRs (Sdtrig) and a debug module
- Spike diff support for `anv32im2` (the trace flow currently runs `anv32im1`)

## SoC

- Access faults for addresses with no slave behind them, checked in the core
  so the trap is precise
- I2C0 on the shared register front end, so it gets the atomic aliases too
- AXI-Lite bridge for Zynq (PYNQ-Z2) and for the Linux-capable core
- GPIO, SPI, timer, PWM, watchdog and a second UART. The address slots and,
  for GPIO and SYSCTRL, the register layouts are already defined; see
  [memory_map.md](memory_map.md#register-status).
- SYSCTRL board ID / build ID / status registers
- DMA / stream engine for the NN accelerator

## NN accelerator

The current block is a first experiment: one int8 dense layer at a time, with
optional ReLU and argmax, fed from its own scratch memory. Next:

- More layer types and multi-layer networks without CPU work between layers
- DMA / stream engine to move data without the CPU
- Higher throughput (more lanes, overlapping fetch and compute)
- Interrupt-driven use in the demos instead of polling

## I2C

The current controller supports START, repeated START, byte TX/RX, ACK/NACK,
STOP, clock stretching with timeout, arbitration-lost detection, a command
queue with RX FIFO, bus busy/free checks, bus recovery and sticky error bits.

Next:

- Make `SCL_LOW`, `SCL_HIGH` and `STRETCH_TIMEOUT` runtime registers instead
  of RTL parameters (their offsets are already reserved)
- A choice between halting the command queue or continuing after
  NACK/arbitration loss/timeout
- Separate IRQ status/enable bits for RX ready, command done, queue empty,
  error and recovery done
- FIFO level counters in the status register
- Better stuck-low reporting when recovery fails
- Simulation tests for queue/RX overflow, NACK, arbitration loss, clock
  stretching, recovery and repeated START
