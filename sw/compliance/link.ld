/* Linker script for riscv-tests and riscv-arch-test. Same layout as
 * riscv-tests env/p/link.ld: code starts at 0x80000000, Spike's reset
 * address, so Spike and the cores run identical binaries. tb_core_test is
 * built with RESET_PC = 0x80000000 for these runs. */
OUTPUT_ARCH("riscv")
ENTRY(_start)

SECTIONS
{
  . = 0x80000000;
  .text.init : { *(.text.init) }
  . = ALIGN(0x1000);
  .tohost : { *(.tohost) }
  . = ALIGN(0x1000);
  .text : { *(.text) }
  . = ALIGN(0x1000);
  .data : { *(.data) }
  .bss : { *(.bss) }
  _end = .;
}
