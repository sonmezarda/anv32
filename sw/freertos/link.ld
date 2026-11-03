/*
 * FreeRTOS programs on the SoC: the 31 KiB of the default 32 KiB BRAM below
 * the UART bootloader (anv32_soc_top BRAM_ADDR_W = 13, BOOT_SIZE = 1024).
 * Same layout as sw/common/link.ld, plus the .bss bounds for crt0.S and the
 * interrupt stack for the FreeRTOS port, which reuses main()'s stack: main()
 * never runs again once the scheduler has started.
 */
OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY {
  RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 31K
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
    . = ALIGN(4);
    _bss_start = .;
    *(.sbss .sbss.*)
    *(.bss .bss.*)
    *(COMMON)
    . = ALIGN(4);
    _bss_end = .;
  } > RAM

  . = ALIGN(16);
  _stack_top = ORIGIN(RAM) + LENGTH(RAM);
  __freertos_irq_stack_top = _stack_top;
}
