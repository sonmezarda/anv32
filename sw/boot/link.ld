/*
 * The UART bootloader (bootloader.S): the top 1 KiB of the default 32 KiB
 * BRAM, where anv32_soc_top (HAS_BOOTLOADER, BOOT_SIZE = 1024) resets the
 * core. Programs get the 31 KiB below it. The code is position independent,
 * so tools/merge_boot_image.py can place the same image under a smaller BRAM.
 */
OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY {
  BOOT (rx) : ORIGIN = 0x00007C00, LENGTH = 1K
}

SECTIONS {
  .text : {
    *(.text.init)
    *(.text .text.*)
    *(.rodata .rodata.*)
  } > BOOT

  /DISCARD/ : {
    *(.data .data.* .sdata .sdata.* .bss .bss.* .sbss .sbss.*)
  }
}
