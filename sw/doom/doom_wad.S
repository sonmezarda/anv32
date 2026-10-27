/* The IWAD is linked into the image; syscalls.c serves it as a file. */
    .section .rodata.doom_wad, "a"
    .balign 4
    .global doom_wad_start
    .global doom_wad_end
doom_wad_start:
    .incbin "doom1.wad"
doom_wad_end:
