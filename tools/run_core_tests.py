#!/usr/bin/env python3
"""Build and run the self-checking tests in sw/tests on every core.

Two suites:
  core  assembly tests on the bare core (sim/tb/common/tb_core_test.sv)
  soc   C tests on the full SoC (sim/tb/soc/tb_soc_test.sv)
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

from run_benchmarks import CORE_DEFINES, CORE_FEATURES, CORE_SOURCES, QUIET_WARNINGS, parse_csv, run


CORE_TYPES = {"anv32i1": 0, "anv32im1": 1, "anv32im2": 2}

SOC_SOURCES = [
    "rtl/include/anv32_bus_pkg.sv",
    "rtl/include/anv32_soc_addr_pkg.sv",
    "rtl/include/anv32_sysctrl_regs_pkg.sv",
    "rtl/include/anv32_gpio_regs_pkg.sv",
    "rtl/include/anv32_uart_regs_pkg.sv",
    "rtl/include/anv32_i2c_regs_pkg.sv",
    "rtl/include/anv32_nn_regs_pkg.sv",
    "rtl/peripherals/uart/core/uart_baud_rate.sv",
    "rtl/peripherals/uart/core/uart_fifo.sv",
    "rtl/peripherals/uart/core/uart_rx.sv",
    "rtl/peripherals/uart/core/uart_tx.sv",
    "rtl/peripherals/uart/core/uart_top.sv",
    "rtl/peripherals/i2c/core/i2c_byte_master_timed.sv",
    "rtl/peripherals/i2c/core/i2c_cmd_master_timed.sv",
    "rtl/peripherals/i2c/i2c_periph.sv",
    "rtl/soc/bus/anv32_bus_decoder.sv",
    "rtl/soc/bus/anv32_bus_bridge.sv",
    "rtl/soc/bus/anv32_bus_regs.sv",
    "rtl/soc/bus/anv32_bus_read_pipe.sv",
    "rtl/peripherals/sysctrl/sysctrl_periph.sv",
    "rtl/peripherals/gpio/gpio_periph.sv",
    "rtl/peripherals/uart/uart_periph.sv",
    "rtl/peripherals/nn_accelerator/int8_dot4.sv",
    "rtl/peripherals/nn_accelerator/dot_product_stream.sv",
    "rtl/peripherals/nn_accelerator/mem_dot_product_stream.sv",
    "rtl/peripherals/nn_accelerator/dense_layer_engine.sv",
    "rtl/peripherals/nn_accelerator/nn_accel_periph.sv",
    "rtl/soc/anv32_soc_top.sv",
]

RESULT_RE = re.compile(r"^TEST_RESULT status=(?P<status>\w+) code=(?P<code>\d+) cycles=(?P<cycles>\d+)")


def load_tests(path: Path) -> list[dict]:
    with path.open() as f:
        tests = json.load(f)
    for test in tests:
        test.setdefault("requires", [])
    return tests


def build_program(args: argparse.Namespace, repo: Path, test: dict, out_dir: Path) -> Path:
    """Build a test image and return its base path (without .hex)."""
    prog_dir = out_dir / "programs" / test["name"]
    prog_dir.mkdir(parents=True, exist_ok=True)
    is_c = test["src"].endswith(".c")
    run(
        [
            args.python,
            "tools/build_rv32_program.py" if is_c else "tools/build_rv32_asm_program.py",
            "--src", test["src"],
            "--out-dir", str(prog_dir),
            "--name", test["name"],
            "--linker", args.linker,
            "--cc", args.cc,
            "--march", test.get("march", "rv32i_zicsr"),
            "--mabi", args.mabi,
            "--objcopy", args.objcopy,
            "--objdump", args.objdump,
            "--bin-to-hex", "tools/bin_to_hex.py",
            "--split-hex", "tools/split_hex.py",
            "--python", args.python,
            *(["--crt0", "sw/common/crt0.S", "--opt=-Os"] if is_c else []),
        ],
        cwd=repo,
        verbose=args.verbose,
    )
    return prog_dir / test["name"]


def soc_sources() -> list[str]:
    sources: list[str] = []
    for core_sources in CORE_SOURCES.values():
        sources.extend(src for src in core_sources if src not in sources)
    return sources + SOC_SOURCES


def build_tb(args: argparse.Namespace, repo: Path, suite: str, core: str, out_dir: Path,
             reset_pc: int = 0) -> Path:
    mdir = out_dir / "obj" / f"{suite}_{core}"
    mdir.mkdir(parents=True, exist_ok=True)
    if suite == "soc":
        top = "tb_soc_test"
        design = [f"-GCORE_TYPE={CORE_TYPES[core]}", *soc_sources(), "sim/tb/soc/tb_soc_test.sv"]
    else:
        top = "tb_core_test"
        design = [f"-D{CORE_DEFINES[core]}", f"-GRESET_PC=32'h{reset_pc:08x}",
                  *CORE_SOURCES[core], "sim/tb/common/tb_core_test.sv"]
    run(
        [
            args.verilator,
            "-sv",
            "--binary",
            "--timing",
            "-Wall",
            "-Wno-fatal",
            *([] if args.warn else QUIET_WARNINGS),
            "-Mdir", str(mdir),
            "--top-module", top,
            *design,
        ],
        cwd=repo,
        verbose=args.verbose,
    )
    return mdir / f"V{top}"


def run_test(args: argparse.Namespace, repo: Path, sim: Path, prog: Path, test: dict,
             mem_wait: bool | int) -> dict:
    """mem_wait: False = none, True = random wait states, n = every access waits n cycles."""
    cmd = [str(sim), f"+prog={prog}", f"+max_cycles={test.get('max_cycles', 200000)}"]
    if mem_wait is True:
        cmd.append("+mem_wait")
    elif mem_wait:
        cmd.append(f"+mem_wait_fixed={mem_wait}")
    proc = subprocess.run(cmd, cwd=repo, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if args.verbose:
        print(proc.stdout, end="")
    for line in proc.stdout.splitlines():
        m = RESULT_RE.match(line)
        if m:
            return {"status": m["status"], "code": int(m["code"]), "cycles": int(m["cycles"])}
    return {"status": "ERROR", "code": 0, "cycles": 0, "output": proc.stdout}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cores", default="anv32i1,anv32im1,anv32im2")
    parser.add_argument("--suites", default="core,soc")
    parser.add_argument("--tests", default="all")
    parser.add_argument("--core-test-list", default="sw/tests/tests.json")
    parser.add_argument("--soc-test-list", default="sw/tests/soc/tests.json")
    parser.add_argument("--out-dir", default="build/core_tests")
    parser.add_argument("--no-mem-wait", action="store_true",
                        help="skip the extra wait-state run on cores with mem_ready")
    parser.add_argument("--verbose", action="store_true")
    parser.add_argument("--warn", action="store_true")
    parser.add_argument("--python", default="python3")
    parser.add_argument("--verilator", default="verilator")
    parser.add_argument("--cc", default="riscv64-unknown-elf-gcc")
    parser.add_argument("--objcopy", default="riscv64-unknown-elf-objcopy")
    parser.add_argument("--objdump", default="riscv64-unknown-elf-objdump")
    parser.add_argument("--mabi", default="ilp32")
    parser.add_argument("--linker", default="sw/common/link.ld")
    args = parser.parse_args()

    repo = Path.cwd()
    out_dir = Path(args.out_dir)
    cores = parse_csv(args.cores)
    unknown = sorted(set(cores) - set(CORE_SOURCES))
    if unknown:
        raise SystemExit(f"unknown core(s): {', '.join(unknown)}")

    suites = parse_csv(args.suites)
    lists = {"core": Path(args.core_test_list), "soc": Path(args.soc_test_list)}
    unknown = sorted(set(suites) - set(lists))
    if unknown:
        raise SystemExit(f"unknown suite(s): {', '.join(unknown)}")

    tests = {suite: load_tests(lists[suite]) for suite in suites}
    if args.tests != "all":
        wanted = set(parse_csv(args.tests))
        missing = wanted - {t["name"] for suite_tests in tests.values() for t in suite_tests}
        if missing:
            raise SystemExit(f"unknown test(s): {', '.join(sorted(missing))}")
        tests = {suite: [t for t in suite_tests if t["name"] in wanted] for suite, suite_tests in tests.items()}

    images = {t["name"]: build_program(args, repo, t, out_dir) for suite_tests in tests.values() for t in suite_tests}

    results = []
    for suite in suites:
        if not tests[suite]:
            continue
        for core in cores:
            print(f"BUILD suite={suite} core={core}", flush=True)
            sim = build_tb(args, repo, suite, core, out_dir)
            waits = suite == "core" and "mem_ready" in CORE_FEATURES[core] and not args.no_mem_wait
            for test in tests[suite]:
                if not set(test["requires"]).issubset(CORE_FEATURES[core]):
                    continue
                prog = images[test["name"]]
                if suite == "core":
                    prog = prog.with_suffix(".hex")
                # A test can also ask for fixed wait states on every access, so a
                # stall is guaranteed rather than left to the random pattern.
                variants = [False] + ([True, *test.get("mem_wait_fixed", [])] if waits else [])
                for mem_wait in variants:
                    result = run_test(args, repo, sim, prog, test, mem_wait)
                    result.update({"test": test["name"], "core": core, "mem_wait": mem_wait})
                    results.append(result)
                    if result["status"] == "ERROR":
                        print(result["output"], end="")

    print()
    print(f"{'test':<18} {'core':<9} {'wait':<5} {'status':<8} {'code':>4} {'cycles':>7}")
    print(f"{'-' * 18} {'-' * 9} {'-' * 5} {'-' * 8} {'-' * 4} {'-' * 7}")
    for r in results:
        code = "" if r["status"] == "PASS" else str(r["code"])
        mw = r["mem_wait"]
        wait = ("yes" if mw else "") if isinstance(mw, bool) else f"={mw}"
        print(f"{r['test']:<18} {r['core']:<9} {wait:<5} "
              f"{r['status']:<8} {code:>4} {r['cycles']:>7}")

    failed = [r for r in results if r["status"] != "PASS"]
    print()
    print(f"{len(results) - len(failed)}/{len(results)} passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
