/* corebench memory layout: one 64 KiB RAM at address 0 (tb_corebench
   RAM_BYTES), code first, stack growing down from the top. */
OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY {
  RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 64K
}

_stack_size = 8K;

SECTIONS {
  .text : {
    *(.text.init)
    *(.text .text.*)
  } > RAM

  .rodata : {
    *(.rodata .rodata.* .srodata .srodata.*)
  } > RAM

  .data : {
    *(.data .data.* .sdata .sdata.*)
  } > RAM

  .bss (NOLOAD) : ALIGN(4) {
    _bss_start = .;
    *(.sbss .sbss.* .bss .bss.* COMMON)
    . = ALIGN(4);
    _bss_end = .;
  } > RAM

  _end = .;
  _stack_top = ORIGIN(RAM) + LENGTH(RAM);
  ASSERT(_end + _stack_size <= _stack_top, "corebench: program leaves less than _stack_size for the stack")
}
