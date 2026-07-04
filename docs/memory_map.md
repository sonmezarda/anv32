# ANV32 Memory Map

This document records the stable target address map for the ANV32 SoC. The
current RTL still has some direct-decode legacy addresses; new software and
future bus work should converge on this map.

## Top-Level Regions

| Address range | Size | Use |
| --- | ---: | --- |
| `0x0000_0000` - `0x0000_FFFF` | 64 KiB | On-chip BRAM / boot RAM |
| `0x0001_0000` - `0x0001_FFFF` | 64 KiB | Reserved boot ROM or extra local RAM |
| `0x1000_0000` - `0x1000_FFFF` | 64 KiB | Low-speed MMIO peripherals |
| `0x1001_0000` - `0x1001_FFFF` | 64 KiB | NN accelerator aperture |
| `0x1002_0000` - `0x1002_FFFF` | 64 KiB | DMA / stream engine aperture |
| `0x1003_0000` - `0x100F_FFFF` | 832 KiB | Reserved accelerator apertures |
| `0x2000_0000` - `0x2FFF_FFFF` | 256 MiB | Reserved external memory-mapped devices |
| `0x8000_0000` - `0x8FFF_FFFF` | 256 MiB | Reserved external RAM / PSRAM / SDRAM |

## Low-Speed MMIO Slots

Low-speed peripherals use 4 KiB slots under `0x1000_0000`.

| Base | Slot | Peripheral |
| --- | ---: | --- |
| `0x1000_0000` | 4 KiB | SYSCTRL: LEDs, board ID, build ID, reset/status |
| `0x1000_1000` | 4 KiB | GPIO0 |
| `0x1000_2000` | 4 KiB | UART0 |
| `0x1000_3000` | 4 KiB | I2C0 |
| `0x1000_4000` | 4 KiB | SPI0 |
| `0x1000_5000` | 4 KiB | TIMER0 |
| `0x1000_6000` | 4 KiB | PWM0 |
| `0x1000_7000` | 4 KiB | IRQ controller / PLIC-lite |
| `0x1000_8000` | 4 KiB | Watchdog |
| `0x1000_9000` | 4 KiB | UART1 / debug UART |
| `0x1000_A000` - `0x1000_FFFF` | 24 KiB | Reserved |

## Accelerator Apertures

Large memories and accelerator-local scratch spaces do not live in the
low-speed peripheral slots. They get separate apertures.

| Base | Use |
| --- | --- |
| `0x1001_0000` | NN accelerator register block |
| `0x1001_1000` | NN accelerator scratch / tensor memory |
| `0x1002_0000` | DMA / stream engine register block |

## Source Headers

- C global map constants: `sw/include/anv32_mmio.h`
- C register layouts: `sw/include/anv32_sysctrl.h`, `sw/include/anv32_gpio.h`,
  `sw/include/anv32_uart.h`, `sw/include/anv32_i2c.h`, and
  `sw/include/anv32_nn.h`
- SystemVerilog global map constants: `rtl/include/anv32_soc_addr_pkg.sv`
- SystemVerilog register layouts: `rtl/include/anv32_*_regs_pkg.sv`
