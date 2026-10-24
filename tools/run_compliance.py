#!/usr/bin/env python3
"""Run riscv-tests and riscv-arch-test on the anv32 cores.

riscv-tests (suites rv32ui, rv32um, rv32mi) are self-checking: each test
writes its result to `tohost`.

riscv-arch-test (suites arch-I, arch-M, arch-privilege) write a signature to
memory. The same ELF runs on Spike, the RISC-V reference simulator, and on the
core; the two signatures must match word for word. These suites need `spike`.

Both repositories are cloned at pinned versions into build/third_party on
first use. Binaries are linked at 0x80000000 (Spike's reset address) and the
testbench is built with the same reset PC.
"""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path

from run_benchmarks import CORE_FEATURES, CORE_SOURCES, parse_csv, run
from run_core_tests import RESULT_RE, build_tb

RISCV_TESTS_URL = "https://github.com/riscv-software-src/riscv-tests.git"
RISCV_TESTS_COMMIT = "3df703cd52d5f0d8224e3c50bf03c6cb70efff98"
ARCH_TEST_URL = "https://github.com/riscv-non-isa/riscv-arch-test.git"
ARCH_TEST_TAG = "3.9.1"

RESET_PC = 0x80000000

RISCV_TESTS_SUITES = ["rv32ui", "rv32um", "rv32mi"]
ARCH_SUITES = {"arch-I": "I", "arch-M": "M", "arch-privilege": "privilege"}
NEEDS_M = {"rv32um", "arch-M"}

# Tests that need features the cores do not implement. Each entry says why.
SKIPPED = {
    "rv32ui-fence_i": "Zifencei is not implemented",
    "rv32ui-ma_data": "misaligned loads/stores are not supported",
    "rv32mi-breakpoint": "Sdtrig (debug triggers) is not implemented",
    "rv32mi-pmpaddr": "needs PMP entries; the cores implement zero (allowed by the spec)",
}


def clone(args: argparse.Namespace, url: str, dest: Path, ref: str, submodules: list[str]) -> None:
    if dest.is_dir():
        return
    dest.parent.mkdir(parents=True, exist_ok=True)
    run(["git", "clone", "-q", url, str(dest)], cwd=Path.cwd(), verbose=args.verbose)
    run(["git", "checkout", "-q", ref], cwd=dest, verbose=args.verbose)
    for sub in submodules:
        run(["git", "submodule", "update", "--init", "-q", sub], cwd=dest, verbose=args.verbose)


def symbol(args: argparse.Namespace, elf: Path, name: str) -> int:
    out = run([args.nm, str(elf)], cwd=Path.cwd(), verbose=False)
    return next(int(line.split()[0], 16) for line in out.splitlines() if line.endswith(f" {name}"))


def build_elf(args: argparse.Namespace, src: Path, work: Path, march: str, includes: list[Path],
              defines: list[str], entry: str = "_start") -> tuple[Path, Path]:
    """Compile one test; return its ELF and word hex image."""
    work.mkdir(parents=True, exist_ok=True)
    elf = work / f"{src.stem}.elf"
    binary = work / f"{src.stem}.bin"
    hexfile = work / f"{src.stem}.hex"
    repo = Path.cwd()
    run(
        [
            args.cc, f"-march={march}", "-mabi=ilp32", "-static", "-mcmodel=medany",
            "-fvisibility=hidden", "-nostdlib", "-nostartfiles",
            *[f"-I{inc}" for inc in includes], *[f"-D{d}" for d in defines],
            "-T", "sw/compliance/link.ld", f"-Wl,--entry={entry}", str(src), "-o", str(elf),
        ],
        cwd=repo,
        verbose=args.verbose,
    )
    run([args.objcopy, "-O", "binary", str(elf), str(binary)], cwd=repo, verbose=args.verbose)
    run([args.python, "tools/bin_to_hex.py", str(binary), str(hexfile)], cwd=repo, verbose=args.verbose)
    return elf, hexfile


def case_defines(src: Path) -> list[str]:
    """Macros a riscv-arch-test asks for in its RVTEST_CASE lines ("def X=Y")."""
    found = re.findall(r"def\s+(\w+)\s*=\s*(\w+)", src.read_text())
    return sorted({f"{name}={value}" for name, value in found})


def collect_tests(args: argparse.Namespace, suites: list[str], out_dir: Path) -> list[dict]:
    third = Path(args.third_party)
    wanted = None if args.tests == "all" else set(parse_csv(args.tests))
    tests: list[dict] = []

    if any(s in RISCV_TESTS_SUITES for s in suites):
        root = third / "riscv-tests"
        clone(args, RISCV_TESTS_URL, root, RISCV_TESTS_COMMIT, ["env"])
        for suite in [s for s in suites if s in RISCV_TESTS_SUITES]:
            for src in sorted((root / "isa" / suite).glob("*.S")):
                name = f"{suite}-{src.stem}"
                if wanted is not None and src.stem not in wanted:
                    continue
                test = {"name": name, "suite": suite, "kind": "riscv-tests"}
                if name not in SKIPPED:
                    march = "rv32im_zicsr" if suite in NEEDS_M else "rv32i_zicsr"
                    test["elf"], test["hex"] = build_elf(
                        args, src, out_dir / "riscv-tests" / name, march,
                        [root / "env" / "p", root / "isa" / "macros" / "scalar"], [])
                tests.append(test)

    arch_suites = [s for s in suites if s in ARCH_SUITES]
    if arch_suites:
        root = third / "riscv-arch-test"
        clone(args, ARCH_TEST_URL, root, ARCH_TEST_TAG, [])
        env = root / "riscv-test-suite" / "env"
        for suite in arch_suites:
            march = "rv32im_zicsr" if suite in NEEDS_M else "rv32i_zicsr"
            src_dir = root / "riscv-test-suite" / "rv32i_m" / ARCH_SUITES[suite] / "src"
            for src in sorted(src_dir.glob("*.S")):
                name = f"{suite}-{src.stem}"
                if wanted is not None and src.stem not in wanted:
                    continue
                elf, hexfile = build_elf(
                    args, src, out_dir / "arch-test" / name, march, [env, Path("sw/compliance")],
                    ["XLEN=32", *case_defines(src)],
                    entry="rvtest_entry_point")
                ref = out_dir / "arch-test" / name / "spike.sig"
                run([args.spike, f"--isa={march}", "--priv=m", f"+signature={ref}",
                     "+signature-granularity=4", str(elf)], cwd=Path.cwd(), verbose=args.verbose)
                tests.append({"name": name, "suite": suite, "kind": "arch-test", "elf": elf,
                              "hex": hexfile, "ref": ref})
    return tests


def run_one(args: argparse.Namespace, sim: Path, test: dict, mem_wait: bool, out_dir: Path) -> dict:
    tohost = symbol(args, test["elf"], "tohost")
    cmd = [str(sim), f"+prog={test['hex']}", f"+tohost={tohost:x}", f"+max_cycles={args.max_cycles}"]
    sig = None
    if test["kind"] == "arch-test":
        sig = test["ref"].with_name(f"{sim.parent.name}{'_wait' if mem_wait else ''}.sig")
        cmd += [f"+signature={sig}",
                f"+sig_begin={symbol(args, test['elf'], 'begin_signature'):x}",
                f"+sig_end={symbol(args, test['elf'], 'end_signature'):x}"]
    if mem_wait:
        cmd.append("+mem_wait")
    proc = subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    result = {"status": "ERROR", "code": 0, "note": ""}
    for line in proc.stdout.splitlines():
        m = RESULT_RE.match(line)
        if m:
            result.update(status=m["status"], code=int(m["code"]))
    if sig is not None and result["status"] == "PASS":
        ref_words = test["ref"].read_text().split()
        dut_words = sig.read_text().split()
        if ref_words != dut_words:
            bad = next((i for i, (r, d) in enumerate(zip(ref_words, dut_words)) if r != d),
                       min(len(ref_words), len(dut_words)))
            result.update(status="FAIL", note=f"signature differs from Spike at word {bad}")
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cores", default="anv32i1,anv32im1,anv32im2")
    parser.add_argument("--suites", default="rv32ui,rv32um,rv32mi,arch-I,arch-M,arch-privilege")
    parser.add_argument("--tests", default="all", help="comma separated test names, e.g. add,div")
    parser.add_argument("--out-dir", default="build/compliance")
    parser.add_argument("--third-party", default="build/third_party")
    parser.add_argument("--max-cycles", type=int, default=2000000)
    parser.add_argument("--no-mem-wait", action="store_true")
    parser.add_argument("--verbose", action="store_true")
    parser.add_argument("--warn", action="store_true")
    parser.add_argument("--python", default="python3")
    parser.add_argument("--verilator", default="verilator")
    parser.add_argument("--spike", default="spike")
    parser.add_argument("--cc", default="riscv64-unknown-elf-gcc")
    parser.add_argument("--objcopy", default="riscv64-unknown-elf-objcopy")
    parser.add_argument("--nm", default="riscv64-unknown-elf-nm")
    args = parser.parse_args()

    suites = parse_csv(args.suites)
    unknown = sorted(set(suites) - set(RISCV_TESTS_SUITES) - set(ARCH_SUITES))
    if unknown:
        raise SystemExit(f"unknown suite(s): {', '.join(unknown)}")
    if any(s in ARCH_SUITES for s in suites) and shutil.which(args.spike) is None:
        raise SystemExit(f"riscv-arch-test suites need Spike ('{args.spike}' not found); "
                         "pass --spike or drop the arch-* suites")

    out_dir = Path(args.out_dir)
    tests = collect_tests(args, suites, out_dir)

    results = []
    for core in parse_csv(args.cores):
        print(f"BUILD tb_core_test core={core}", flush=True)
        sim = build_tb(args, Path.cwd(), "compliance", core, out_dir, reset_pc=RESET_PC)
        variants = [False]
        if "mem_ready" in CORE_FEATURES[core] and not args.no_mem_wait:
            variants.append(True)
        for test in tests:
            if test["suite"] in NEEDS_M and "m" not in CORE_FEATURES[core]:
                continue
            for mem_wait in variants:
                row = {"test": test["name"], "core": core, "mem_wait": mem_wait}
                if test["name"] in SKIPPED:
                    row.update(status="SKIP", code=0, note=SKIPPED[test["name"]])
                else:
                    row.update(run_one(args, sim, test, mem_wait, out_dir))
                results.append(row)

    print()
    print(f"{'test':<30} {'core':<9} {'wait':<5} {'status':<8} {'code':>4}  note")
    print(f"{'-' * 30} {'-' * 9} {'-' * 5} {'-' * 8} {'-' * 4}  {'-' * 4}")
    for r in results:
        if r["status"] == "PASS" and not args.verbose:
            continue
        code = str(r["code"]) if r["status"] == "FAIL" and r["code"] else ""
        print(f"{r['test']:<30} {r['core']:<9} {'yes' if r['mem_wait'] else '':<5} "
              f"{r['status']:<8} {code:>4}  {r['note']}")

    passed = sum(r["status"] == "PASS" for r in results)
    skipped = sum(r["status"] == "SKIP" for r in results)
    failed = len(results) - passed - skipped
    print()
    print(f"{passed} passed, {failed} failed, {skipped} skipped (only non-passing runs are listed)")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
