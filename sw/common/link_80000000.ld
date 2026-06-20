OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY {
  RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 4K
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
