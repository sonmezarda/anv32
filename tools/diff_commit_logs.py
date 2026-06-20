#!/usr/bin/env python3
"""Compare Spike and core normalized commit logs."""

import argparse
import difflib
import re
import sys
from pathlib import Path


LINE_RE = re.compile(
    r"core(?P<core>\d+)\s+pc=(?P<pc>[0-9a-fA-F]+)\s+instr=(?P<instr>[0-9a-fA-F]+)"
    r"(?:\s+write\s+(?P<rd>x\d+)=(?P<value>[0-9a-fA-F]+))?"
)


def parse_log(path):
    events = []
    for lineno, line in enumerate(Path(path).read_text().splitlines(), start=1):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue

        match = LINE_RE.search(stripped)
        if not match:
            continue

        pc = int(match.group("pc"), 16)
        instr = int(match.group("instr"), 16)
        rd = match.group("rd")
        value = match.group("value")
        if rd is None:
            events.append(f"pc={pc:08x} instr={instr:08x}")
        else:
            events.append(f"pc={pc:08x} instr={instr:08x} write {rd}={int(value, 16):08x}")

    return events


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--spike-log", required=True)
    parser.add_argument("--core-log", required=True)
    parser.add_argument("--diff-out", default="")
    return parser.parse_args()


def main():
    args = parse_args()
    spike = parse_log(args.spike_log)
    core = parse_log(args.core_log)

    if not spike:
        print(f"No comparable Spike events found in {args.spike_log}", file=sys.stderr)
        return 2
    if not core:
        print(f"No comparable core events found in {args.core_log}", file=sys.stderr)
        return 2

    if spike == core:
        if args.diff_out:
            diff_path = Path(args.diff_out)
            diff_path.parent.mkdir(parents=True, exist_ok=True)
            diff_path.write_text("")
        print(f"PASS: {len(core)} commit events match Spike")
        return 0

    diff = "\n".join(
        difflib.unified_diff(
            spike,
            core,
            fromfile=args.spike_log,
            tofile=args.core_log,
            lineterm="",
        )
    )
    if args.diff_out:
        diff_path = Path(args.diff_out)
        diff_path.parent.mkdir(parents=True, exist_ok=True)
        diff_path.write_text(diff + "\n")
        print(f"FAIL: commit logs differ; diff written to {diff_path}", file=sys.stderr)
    else:
        print("FAIL: commit logs differ", file=sys.stderr)
    print(diff, file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
