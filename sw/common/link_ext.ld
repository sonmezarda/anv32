/*
 * Programs that run from external RAM (EXT_RAM_BASE) behind the caches:
 * the same layout as link.ld, 64 KiB from 0x80000000. Used by the "ext"
 * suite of tools/run_core_tests.py.
 */
OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY {
  RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 64K
}

SECTIONS {
  . = ORIGIN(RAM);

  .text : {
    *(.text.init)
    *(.text .text.*)
  } > RAM

  .rodata : {
    *(.rodata .rodata.*)
  } > RAM

  .data : {
    *(.sdata .sdata.*)
    *(.data .data.*)
  } > RAM

  .bss (NOLOAD) : {
    *(.sbss .sbss.*)
    *(.bss .bss.*)
    *(COMMON)
  } > RAM

  . = ALIGN(16);
  _stack_top = ORIGIN(RAM) + LENGTH(RAM);
}
