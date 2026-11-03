#!/usr/bin/env python3
"""Merge a program and the UART bootloader into one BRAM image.

Usage:
    merge_boot_image.py prog.hex boot.hex out.hex [--boot-addr 0x7C00]

All three are word hex files (one 32-bit word per line, as bin_to_hex.py
writes). The program starts at 0 and must end below the bootloader; the gap
is zero-filled and the bootloader goes at --boot-addr, the top BOOT_SIZE
bytes of the BRAM (anv32_soc_top HAS_BOOTLOADER).
"""
import argparse
import sys


def read_words(path):
    with open(path) as f:
        return [line.strip() for line in f if line.strip()]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("prog")
    parser.add_argument("boot")
    parser.add_argument("out")
    parser.add_argument("--boot-addr", type=lambda s: int(s, 0), default=0x7C00)
    args = parser.parse_args()

    prog = read_words(args.prog)
    boot = read_words(args.boot)
    boot_word = args.boot_addr // 4
    if len(prog) > boot_word:
        sys.exit(f"{args.prog}: {len(prog) * 4} bytes, more than the "
                 f"{args.boot_addr} bytes below the bootloader")

    words = prog + ["00000000"] * (boot_word - len(prog)) + boot
    with open(args.out, "w") as f:
        f.write("\n".join(words) + "\n")
    print(f"merge {len(prog)} program words + bootloader at "
          f"0x{args.boot_addr:04X} -> {args.out}")


if __name__ == "__main__":
    main()
