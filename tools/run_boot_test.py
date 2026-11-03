#!/usr/bin/env python3
"""Run the UART bootloader test (sim/tb/soc/tb_soc_boot.sv) on every core.

Builds the bootloader, the program already in the BRAM image (boot_app_a)
and the one sent over UART (boot_app_b), merges the first with the
bootloader as `make fpga` does, and runs the testbench once per core.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from run_benchmarks import QUIET_WARNINGS, parse_csv, run
from run_core_tests import CORE_TYPES, RESULT_RE, soc_sources


def build_asm(args, name: str, src: str, linker: str, out_dir: Path) -> Path:
    prog_dir = out_dir / "programs" / name
    run([
        args.python, "tools/build_rv32_asm_program.py",
        "--src", src,
        "--out-dir", str(prog_dir),
        "--name", name,
        "--linker", linker,
        "--march", "rv32i",
    ], cwd=Path.cwd(), verbose=args.verbose)
    return prog_dir / name


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cores", default="anv32i1,anv32im1,anv32im2")
    parser.add_argument("--out-dir", default="build/boot_test")
    parser.add_argument("--verbose", action="store_true")
    parser.add_argument("--python", default="python3")
    parser.add_argument("--verilator", default="verilator")
    args = parser.parse_args()

    repo = Path.cwd()
    out_dir = Path(args.out_dir)
    boot = build_asm(args, "bootloader", "sw/boot/bootloader.S", "sw/boot/link.ld", out_dir)
    app_a = build_asm(args, "boot_app_a", "sw/tests/boot/boot_app_a.S", "sw/common/link.ld", out_dir)
    app_b = build_asm(args, "boot_app_b", "sw/tests/boot/boot_app_b.S", "sw/common/link.ld", out_dir)
    image = out_dir / "programs" / "image"
    run([args.python, "tools/merge_boot_image.py", f"{app_a}.hex", f"{boot}.hex",
         f"{image}.hex"], cwd=repo, verbose=args.verbose)
    run([args.python, "tools/split_hex.py", f"{image}.hex", str(image)],
        cwd=repo, verbose=args.verbose)

    results = []
    for core in parse_csv(args.cores):
        mdir = out_dir / "obj" / core
        mdir.mkdir(parents=True, exist_ok=True)
        print(f"BUILD boot core={core}", flush=True)
        run([
            args.verilator, "-sv", "--binary", "--timing", "-Wall", "-Wno-fatal",
            *QUIET_WARNINGS,
            "-Mdir", str(mdir),
            "--top-module", "tb_soc_boot",
            f"-GCORE_TYPE={CORE_TYPES[core]}",
            *soc_sources(), "sim/tb/soc/tb_soc_boot.sv",
        ], cwd=repo, verbose=args.verbose)
        out = run([str(mdir / "Vtb_soc_boot"), f"+boot_image={image}", f"+app={app_b}.hex"],
                  cwd=repo, verbose=args.verbose)
        status = next((m for m in map(RESULT_RE.match, out.splitlines()) if m), None)
        if args.verbose or not status or status["status"] != "PASS":
            print(out, end="")
        results.append((core, status))

    print()
    print(f"{'core':<9} {'status':<8} {'code':>4} {'cycles':>7}")
    print(f"{'-' * 9} {'-' * 8} {'-' * 4} {'-' * 7}")
    for core, m in results:
        st = m["status"] if m else "ERROR"
        code = "" if st == "PASS" else (m["code"] if m else "")
        print(f"{core:<9} {st:<8} {code:>4} {m['cycles'] if m else '':>7}")
    failed = [r for r in results if not r[1] or r[1]["status"] != "PASS"]
    print()
    print(f"{len(results) - len(failed)}/{len(results)} passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
