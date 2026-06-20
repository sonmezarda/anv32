#!/usr/bin/env python3
"""Run Spike and write raw plus lightly normalized commit logs."""

import argparse
import re
import subprocess
from pathlib import Path


INSTR_RE = re.compile(
    r"core\s+(\d+):\s+0x([0-9a-fA-F]+)\s+\(0x([0-9a-fA-F]+)\)\s*(.*)"
)
REG_RE = re.compile(
    r"core\s+(\d+):\s+\d+\s+0x([0-9a-fA-F]+)\s+\(0x([0-9a-fA-F]+)\)\s+"
    r"(x\d+)\s+0x([0-9a-fA-F]+)(.*)"
)


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--elf", required=True)
    parser.add_argument("--raw-log", required=True)
    parser.add_argument("--norm-log", required=True)
    parser.add_argument("--spike", default="spike")
    parser.add_argument("--isa", default="rv32i_zicsr")
    parser.add_argument("--priv", default="m")
    parser.add_argument("--instructions", type=int, default=200)
    parser.add_argument("--pc-base", default="", help="Optional base address to subtract in normalized log")
    return parser.parse_args()


def main():
    args = parse_args()
    raw_log = Path(args.raw_log)
    norm_log = Path(args.norm_log)
    raw_log.parent.mkdir(parents=True, exist_ok=True)
    norm_log.parent.mkdir(parents=True, exist_ok=True)

    cmd = [
        args.spike,
        f"--isa={args.isa}",
        f"--priv={args.priv}",
        "-l",
        "--log-commits",
        f"--instructions={args.instructions}",
        args.elf,
    ]
    print("+ " + " ".join(cmd), flush=True)
    proc = subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    raw_log.write_text(proc.stdout)

    pc_base = int(args.pc_base, 0) if args.pc_base else None
    normalized = []
    for line in proc.stdout.splitlines():
        reg = REG_RE.search(line)
        if reg:
            core, pc_s, bits, rd, value, extra = reg.groups()
            pc = int(pc_s, 16)
            if pc_base is not None and pc < pc_base:
                continue
            shown_pc = pc - pc_base if pc_base is not None else pc
            tail = f" {extra.strip()}" if extra.strip() else ""
            normalized.append(
                f"core{core} pc={shown_pc:08x} instr={int(bits, 16):08x} write {rd}={int(value, 16):08x}{tail}"
            )
            continue

        instr = INSTR_RE.search(line)
        if instr:
            core, pc_s, bits, asm = instr.groups()
            pc = int(pc_s, 16)
            if pc_base is not None and pc < pc_base:
                continue
            shown_pc = pc - pc_base if pc_base is not None else pc
            normalized.append(f"core{core} pc={shown_pc:08x} instr={int(bits, 16):08x} {asm}".rstrip())
            continue

    if not normalized:
        normalized.append("# No Spike commit lines parsed. See raw log.")

    norm_log.write_text("\n".join(normalized) + "\n")
    if proc.returncode != 0:
        print(f"Spike exited with {proc.returncode}; logs were still written.", flush=True)
    print(f"Spike raw log: {raw_log}", flush=True)
    print(f"Spike normalized log: {norm_log}", flush=True)


if __name__ == "__main__":
    main()
