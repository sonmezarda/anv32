# Memory Map

Address map of the ANV32 SoC. Regions and slots marked "reserved" have
addresses assigned but no hardware behind them yet.

## Top-Level Regions

| Address range | Size | Use |
| --- | ---: | --- |
| `0x0000_0000` - `0x0000_FFFF` | 64 KiB | On-chip BRAM (4 KiB populated in the current build) |
| `0x0001_0000` - `0x0001_FFFF` | 64 KiB | Reserved boot ROM or extra local RAM |
| `0x1000_0000` - `0x1000_FFFF` | 64 KiB | Low-speed MMIO peripherals |
| `0x1001_0000` - `0x1001_FFFF` | 64 KiB | NN accelerator aperture |
| `0x1002_0000` - `0x1002_FFFF` | 64 KiB | Reserved: DMA / stream engine |
| `0x1003_0000` - `0x100F_FFFF` | 832 KiB | Reserved accelerator apertures |
| `0x2000_0000` - `0x2FFF_FFFF` | 256 MiB | Reserved external memory-mapped devices |
| `0x8000_0000` - `0x8FFF_FFFF` | 256 MiB | Reserved external RAM / PSRAM / SDRAM |

## Low-Speed MMIO Slots

Low-speed peripherals use 4 KiB slots under `0x1000_0000`.

| Base | Slot | Peripheral |
| --- | ---: | --- |
| `0x1000_0000` | 4 KiB | SYSCTRL (LED register implemented; board/build ID reserved) |
| `0x1000_1000` | 4 KiB | GPIO0 (only the IRQ pending register is implemented) |
| `0x1000_2000` | 4 KiB | UART0 |
| `0x1000_3000` | 4 KiB | I2C0 |
| `0x1000_4000` | 4 KiB | Reserved: SPI0 |
| `0x1000_5000` | 4 KiB | Reserved: TIMER0 |
| `0x1000_6000` | 4 KiB | Reserved: PWM0 |
| `0x1000_7000` | 4 KiB | Reserved: IRQ controller / PLIC-lite |
| `0x1000_8000` | 4 KiB | Reserved: Watchdog |
| `0x1000_9000` | 4 KiB | Reserved: UART1 / debug UART |
| `0x1000_A000` - `0x1000_FFFF` | 24 KiB | Reserved |

## Register Status

The register headers already define the planned layout of each peripheral.
Some of those registers have no hardware behind them yet:

| Peripheral | Implemented | Defined, not implemented yet |
| --- | --- | --- |
| SYSCTRL | `LED` | `STATUS`, `BOARD_ID`, `BUILD_ID` |
| GPIO0 | `IRQ_PENDING` (one interrupt input, write 1 to clear) | `DATA`, `DIR`, `OUT_SET`, `OUT_CLR`, `IRQ_ENABLE` |
| UART0 | `TXDATA`, `STATUS`, `BAUD`, `ERROR`, `RXDATA` | |
| I2C0 | `CMD`, `STATUS`, `RXDATA`, `CTRL` | `SCL_LOW`, `SCL_HIGH`, `TIMEOUT` (timing is an RTL parameter for now) |
| NN | all registers | |

Data accesses to an address with no hardware behind it ignore writes and read
as zero. This covers unimplemented registers, reserved slots and reserved
regions. Raising an access fault instead is on the [roadmap](roadmap.md).
The exception is the BRAM region: addresses above the populated 4 KiB wrap
around onto it.

## Accelerator Apertures

Large memories and accelerator-local scratch spaces do not live in the
low-speed peripheral slots. They get separate apertures.

| Base | Use |
| --- | --- |
| `0x1001_0000` | NN accelerator register block |
| `0x1001_1000` | NN accelerator scratch / tensor memory |
| `0x1002_0000` | Reserved: DMA / stream engine register block |

## Source Headers

- C global map constants: `sw/include/anv32_mmio.h`
- C register layouts: `sw/include/anv32_sysctrl.h`, `sw/include/anv32_gpio.h`,
  `sw/include/anv32_uart.h`, `sw/include/anv32_i2c.h`, and
  `sw/include/anv32_nn.h`
- SystemVerilog global map constants: `rtl/include/anv32_soc_addr_pkg.sv`
- SystemVerilog register layouts: `rtl/include/anv32_*_regs_pkg.sv`
