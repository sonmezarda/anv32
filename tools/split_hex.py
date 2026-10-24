#!/usr/bin/env python3
"""Split a 32-bit word hex (one word per line) into 4 byte-lane hex files.

Usage:
    split_hex.py prog.hex                 -> prog_lane0.hex .. prog_lane3.hex
    split_hex.py prog.hex out/base        -> out/base_lane0.hex ..

Lane i holds bits [8*i+7 : 8*i] of each word, matching a byte-lane-split
BRAM whose lane i is initialised with:
    $readmemh($sformatf("%s_lane%0d.hex", INIT_FILE, i), mem)

Each output line is exactly one byte (2 hex digits), so $readmemh fills an
8-bit-wide array element per line. Blank lines and // or # comments in the
source are ignored; @address directives are rejected (lane split needs a
flat word list).
"""
import sys
import os


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: split_hex.py <input.hex> [output_base]")

    src = sys.argv[1]
    if len(sys.argv) >= 3:
        base = sys.argv[2]
    elif src.lower().endswith(".hex"):
        base = src[:-4]
    else:
        base = src

    words = []
    with open(src) as f:
        for lineno, raw in enumerate(f, 1):
            line = raw.strip()
            for c in ("//", "#"):
                i = line.find(c)
                if i != -1:
                    line = line[:i].strip()
            if not line:
                continue
            if line.startswith("@"):
                sys.exit(f"{src}:{lineno}: address directive '{line}' "
                         "not supported; lane split needs a flat word list")
            try:
                words.append(int(line, 16) & 0xFFFFFFFF)
            except ValueError:
                sys.exit(f"{src}:{lineno}: not a hex word: {line!r}")

    out_dir = os.path.dirname(base)
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)

    paths = [f"{base}_lane{i}.hex" for i in range(4)]
    files = [open(p, "w") for p in paths]
    try:
        for w in words:
            for i in range(4):
                files[i].write(f"{(w >> (8 * i)) & 0xFF:02X}\n")
    finally:
        for fp in files:
            fp.close()

    names = ", ".join(os.path.basename(p) for p in paths)
    print(f"split {len(words)} words -> {names}")


if __name__ == "__main__":
    main()
