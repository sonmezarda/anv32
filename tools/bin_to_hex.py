#!/usr/bin/env python3
"""Convert a raw little-endian binary image to one 32-bit hex word per line."""

import argparse
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("input", help="raw binary input")
    parser.add_argument("output", help="word-hex output")
    args = parser.parse_args()

    data = Path(args.input).read_bytes()
    pad = (-len(data)) % 4
    if pad:
        data += bytes(pad)

    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("w") as f:
        for i in range(0, len(data), 4):
            word = int.from_bytes(data[i:i + 4], byteorder="little")
            f.write(f"{word:08X}\n")

    print(f"bin2hex {len(data) // 4} words -> {out}")


if __name__ == "__main__":
    main()
