#!/usr/bin/env python3
"""Build and run the ANV32 synthetic benchmark suite."""

from __future__ import annotations

import argparse
import csv
import json
import re
import subprocess
import sys
from pathlib import Path


COMMON_PKGS = [
    "rtl/include/anv32_config_pkg.sv",
    "rtl/include/anv32_isa_pkg.sv",
]

QUIET_WARNINGS = [
    "-Wno-DECLFILENAME",
    "-Wno-EOFNEWLINE",
    "-Wno-TIMESCALEMOD",
    "-Wno-UNUSEDSIGNAL",
    "-Wno-UNUSEDPARAM",
    "-Wno-WIDTHEXPAND",
    "-Wno-BLKSEQ",
    "-Wno-PINCONNECTEMPTY",
]

CORE_SOURCES = {
    "anv32i1": COMMON_PKGS
    + [
        "rtl/common/mem/anv32_bram_tdp.sv",
        "rtl/core/common/anv32_regfile.sv",
        "rtl/core/common/anv32_alu.sv",
        "rtl/core/common/anv32_decoder.sv",
        "rtl/core/common/anv32_csr.sv",
        "rtl/core/common/anv32_csr_exec.sv",
        "rtl/core/pipe5/anv32_fetch_c1.sv",
        "rtl/core/pipe5/anv32_decode_c1.sv",
        "rtl/core/anv32i1/anv32_execute_i_c1.sv",
        "rtl/core/pipe5/anv32_memory_c1.sv",
        "rtl/core/pipe5/anv32_writeback_c1.sv",
        "rtl/core/anv32i1/anv32i1_top.sv",
        "rtl/core/pipe5/anv32_hazard_basic.sv",
    ],
    "anv32im1": COMMON_PKGS
    + [
        "rtl/core/common/anv32_decoder.sv",
        "rtl/core/common/anv32_csr.sv",
        "rtl/core/common/anv32_csr_exec.sv",
        "rtl/common/mem/anv32_bram_tdp.sv",
        "rtl/core/common/anv32_alu.sv",
        "rtl/core/common/anv32_regfile.sv",
        "rtl/core/pipe5/anv32_fetch_c1.sv",
        "rtl/core/pipe5/anv32_decode_c1.sv",
        "rtl/core/common/anv32_mul_comb.sv",
        "rtl/core/common/anv32_div.sv",
        "rtl/core/anv32im1/anv32_execute_im.sv",
        "rtl/core/pipe5/anv32_memory_c1.sv",
        "rtl/core/pipe5/anv32_writeback_c1.sv",
        "rtl/core/pipe5/anv32_hazard_basic.sv",
        "rtl/core/pipe5/anv32_forward_unit.sv",
        "rtl/core/anv32im1/anv32im1_top.sv",
    ],
    "anv32im2": COMMON_PKGS
    + [
        "rtl/common/mem/anv32_bram_tdp.sv",
        "rtl/core/common/anv32_regfile.sv",
        "rtl/core/common/anv32_alu.sv",
        "rtl/core/common/anv32_decoder.sv",
        "rtl/core/common/anv32_csr.sv",
        "rtl/core/common/anv32_csr_exec.sv",
        "rtl/core/common/anv32_mul_comb.sv",
        "rtl/core/common/anv32_div.sv",
        "rtl/core/pipe5/anv32_hazard_basic.sv",
        "rtl/core/pipe5/anv32_forward_unit.sv",
        "rtl/core/anv32im2/anv32_forward_unit_im2.sv",
        "rtl/core/pipe5/anv32_fetch_c1.sv",
        "rtl/core/pipe5/anv32_decode_c1.sv",
        "rtl/core/anv32im2/anv32_execute_im_c1.sv",
        "rtl/core/anv32im2/anv32_execute_im_c2.sv",
        "rtl/core/pipe5/anv32_memory_c1.sv",
        "rtl/core/pipe5/anv32_writeback_c1.sv",
        "rtl/core/anv32im2/anv32im2_top.sv",
    ],
}

CORE_DEFINES = {
    "anv32i1": "ANV32_BENCH_CORE_ANV32I1",
    "anv32im1": "ANV32_BENCH_CORE_ANV32IM1",
    "anv32im2": "ANV32_BENCH_CORE_ANV32IM2",
}

CORE_FEATURES = {
    "anv32i1": set(),
    "anv32im1": {"m"},
    "anv32im2": {"m"},
}

RESULT_RE = re.compile(r"^BENCH_RESULT\s+(?P<body>.*)$")


def run(cmd: list[str], *, cwd: Path, verbose: bool) -> str:
    if verbose:
        print("+ " + " ".join(cmd), flush=True)
    proc = subprocess.run(
        cmd,
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    if verbose or proc.returncode != 0:
        print(proc.stdout, end="")
    if proc.returncode != 0:
        raise subprocess.CalledProcessError(proc.returncode, cmd, proc.stdout)
    return proc.stdout


def parse_csv(value: str) -> list[str]:
    return [item.strip() for item in value.split(",") if item.strip()]


def load_benchmarks(path: Path) -> list[dict]:
    with path.open() as f:
        benches = json.load(f)
    for bench in benches:
        bench.setdefault("type", "asm")
        bench.setdefault("requires", [])
        bench.setdefault("expected_x10", 1)
    return benches


def parse_fmax(args: argparse.Namespace) -> dict[str, float]:
    fmax: dict[str, float] = {}
    if args.fmax_json:
        with Path(args.fmax_json).open() as f:
            raw = json.load(f)
        for core, value in raw.items():
            if isinstance(value, dict):
                value = value.get("mhz", value.get("fmax_mhz"))
            if value is not None:
                fmax[core] = float(value)

    for item in args.fmax or []:
        for chunk in parse_csv(item):
            if "=" not in chunk:
                raise SystemExit(f"bad --fmax item '{chunk}', expected core=MHz")
            core, mhz = chunk.split("=", 1)
            fmax[core.strip()] = float(mhz)
    return fmax


def compatible(core: str, bench: dict) -> bool:
    return set(bench["requires"]).issubset(CORE_FEATURES[core])


def benchmark_march(core: str, bench: dict) -> str:
    return bench.get("march_by_core", {}).get(core, bench["march"])


def build_program(args: argparse.Namespace, repo: Path, bench: dict, out_dir: Path, core: str) -> Path:
    name = bench["name"]
    march = benchmark_march(core, bench)
    build_type = bench.get("type", "asm")
    opt = bench.get("opt", args.opt)
    variant = f"{name}_{march.replace('_', '-').replace('/', '-')}_{opt.replace('-', '')}"
    prog_dir = out_dir / "programs" / variant
    prog_dir.mkdir(parents=True, exist_ok=True)

    builder = "tools/build_rv32_program.py" if build_type == "c" else "tools/build_rv32_asm_program.py"
    cmd = [
        args.python,
        builder,
        "--src", bench["src"],
        "--out-dir", str(prog_dir),
        "--name", name,
        "--linker", args.linker,
        "--cc", args.cc,
        "--march", march,
        "--mabi", args.mabi,
        "--objcopy", args.objcopy,
        "--objdump", args.objdump,
        "--bin-to-hex", "tools/bin_to_hex.py",
        "--split-hex", "tools/split_hex.py",
        "--python", args.python,
    ]
    if build_type == "c":
        cmd.extend(["--crt0", args.crt0, f"--opt={opt}"])
    run(cmd, cwd=repo, verbose=args.verbose)
    return prog_dir / name


def run_benchmark(
    args: argparse.Namespace,
    repo: Path,
    core: str,
    bench: dict,
    image_base: Path,
    out_dir: Path,
) -> dict:
    mdir = out_dir / "obj" / f"{core}_{bench['name']}"
    mdir.mkdir(parents=True, exist_ok=True)
    max_cycles = int(args.max_cycles or bench["max_cycles"])
    cmd = [
        args.verilator,
        "-sv",
        "--binary",
        "--timing",
        "-Wall",
        "-Wno-fatal",
        *([] if args.warn else QUIET_WARNINGS),
        "-Mdir",
        str(mdir),
        f"-D{CORE_DEFINES[core]}",
        "--top-module",
        "tb_benchmark",
        f"-GINIT_FILE=\"{image_base}\"",
        f"-GMAX_CYCLES={max_cycles}",
        f"-GPC_RESET_VALUE={args.pc_reset_value}",
        f"-GEXPECT_X10={int(bench['expected_x10'])}",
        *CORE_SOURCES[core],
        "sim/tb/common/tb_benchmark.sv",
    ]
    run(cmd, cwd=repo, verbose=args.verbose)
    sim_out = run([str(mdir / "Vtb_benchmark")], cwd=repo, verbose=args.verbose)

    result = parse_result(sim_out)
    result.update(
        {
            "core": core,
            "benchmark": bench["name"],
            "tags": ",".join(bench.get("tags", [])),
            "type": bench.get("type", "asm"),
            "march": benchmark_march(core, bench),
            "max_cycles": max_cycles,
        }
    )
    return result


def parse_result(output: str) -> dict:
    for line in output.splitlines():
        match = RESULT_RE.match(line.strip())
        if not match:
            continue
        values: dict[str, str | int] = {}
        for token in match.group("body").split():
            key, value = token.split("=", 1)
            if value.startswith("0x"):
                values[key] = int(value, 16)
            elif value.isdigit():
                values[key] = int(value)
            else:
                values[key] = value
        return values
    raise RuntimeError("simulation did not emit BENCH_RESULT")


def enrich(result: dict, fmax: dict[str, float]) -> None:
    cycles = int(result["cycles"])
    commits = int(result["commits"])
    result["cpi"] = cycles / commits if commits else None
    mhz = fmax.get(result["core"])
    if mhz is None:
        result["fmax_mhz"] = None
        result["time_us"] = None
        result["effective_mips"] = None
        return
    result["fmax_mhz"] = mhz
    result["time_us"] = cycles / mhz
    result["effective_mips"] = commits * mhz / cycles if cycles else None


def write_outputs(out_dir: Path, results: list[dict]) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    json_path = out_dir / "results.json"
    csv_path = out_dir / "results.csv"
    with json_path.open("w") as f:
        json.dump(results, f, indent=2, sort_keys=True)
        f.write("\n")

    if not results:
        csv_path.write_text("")
        return

    fields = [
        "benchmark",
        "core",
        "type",
        "status",
        "cycles",
        "commits",
        "cpi",
        "fmax_mhz",
        "time_us",
        "effective_mips",
        "branches",
        "branches_taken",
        "branches_not_taken",
        "static_nt_branch_mispredicts",
        "static_nt_mispredicts",
        "raw_stall_cycles",
        "load_use_stall_cycles",
        "branch_redirect_cycles",
        "muldiv_stall_cycles",
        "mem_wait_stall_cycles",
        "loads",
        "stores",
        "alu_ops",
        "muldiv_ops",
        "final_x10",
        "expected_x10",
        "tags",
    ]
    with csv_path.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(results)


def fmt_float(value: object, digits: int = 2) -> str:
    if value is None:
        return "-"
    return f"{float(value):.{digits}f}"


def print_table(results: list[dict]) -> None:
    headers = [
        "benchmark",
        "core",
        "type",
        "status",
        "cycles",
        "commits",
        "CPI",
        "MHz",
        "time_us",
        "MIPS",
        "br",
        "taken",
        "nt",
        "misp_nt",
        "raw_stall",
        "load_use",
        "br_redir",
        "md_stall",
        "mem_wait",
    ]
    rows = []
    for r in results:
        rows.append(
            [
                r["benchmark"],
                r["core"],
                r.get("type", "asm"),
                r["status"],
                str(r["cycles"]),
                str(r["commits"]),
                fmt_float(r["cpi"], 3),
                fmt_float(r["fmax_mhz"], 2),
                fmt_float(r["time_us"], 3),
                fmt_float(r["effective_mips"], 2),
                str(r["branches"]),
                str(r["branches_taken"]),
                str(r["branches_not_taken"]),
                str(r["static_nt_branch_mispredicts"]),
                str(r.get("raw_stall_cycles", 0)),
                str(r.get("load_use_stall_cycles", 0)),
                str(r.get("branch_redirect_cycles", 0)),
                str(r.get("muldiv_stall_cycles", 0)),
                str(r.get("mem_wait_stall_cycles", 0)),
            ]
        )

    widths = [len(h) for h in headers]
    for row in rows:
        widths = [max(w, len(cell)) for w, cell in zip(widths, row)]
    print("  ".join(h.ljust(w) for h, w in zip(headers, widths)))
    print("  ".join("-" * w for w in widths))
    for row in rows:
        print("  ".join(cell.ljust(w) for cell, w in zip(row, widths)))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cores", default="anv32i1,anv32im1,anv32im2")
    parser.add_argument("--benchmarks", default="all")
    parser.add_argument("--bench-list", default="sw/benchmarks/benchmarks.json")
    parser.add_argument("--out-dir", default="build/bench")
    parser.add_argument("--max-cycles", type=int)
    parser.add_argument("--pc-reset-value", default="0")
    parser.add_argument("--fmax-json")
    parser.add_argument("--fmax", action="append", help="core=MHz, or comma separated pairs")
    parser.add_argument("--keep-going", action="store_true")
    parser.add_argument("--verbose", action="store_true")
    parser.add_argument("--warn", action="store_true")
    parser.add_argument("--python", default="python3")
    parser.add_argument("--verilator", default="verilator")
    parser.add_argument("--cc", default="riscv64-unknown-elf-gcc")
    parser.add_argument("--objcopy", default="riscv64-unknown-elf-objcopy")
    parser.add_argument("--objdump", default="riscv64-unknown-elf-objdump")
    parser.add_argument("--mabi", default="ilp32")
    parser.add_argument("--linker", default="sw/common/link.ld")
    parser.add_argument("--crt0", default="sw/common/crt0.S")
    parser.add_argument("--opt", default="-Os")
    args = parser.parse_args()

    repo = Path.cwd()
    out_dir = Path(args.out_dir)
    cores = parse_csv(args.cores)
    unknown = sorted(set(cores) - set(CORE_SOURCES))
    if unknown:
        raise SystemExit(f"unknown core(s): {', '.join(unknown)}")

    benches = load_benchmarks(Path(args.bench_list))
    if args.benchmarks != "all":
        wanted = set(parse_csv(args.benchmarks))
        benches = [b for b in benches if b["name"] in wanted or wanted.intersection(b.get("tags", []))]
        missing = wanted - {b["name"] for b in benches} - set().union(*(set(b.get("tags", [])) for b in benches), set())
        if missing:
            raise SystemExit(f"unknown benchmark/tag(s): {', '.join(sorted(missing))}")

    fmax = parse_fmax(args)
    results: list[dict] = []
    failures = 0
    image_cache: dict[tuple[str, str, str, str], Path] = {}

    for bench in benches:
        for core in cores:
            if not compatible(core, bench):
                continue
            try:
                opt = bench.get("opt", args.opt)
                cache_key = (bench["name"], benchmark_march(core, bench), bench.get("type", "asm"), opt)
                if cache_key not in image_cache:
                    image_cache[cache_key] = build_program(args, repo, bench, out_dir, core)
                print(f"RUN benchmark={bench['name']} core={core}", flush=True)
                result = run_benchmark(args, repo, core, bench, image_cache[cache_key], out_dir)
                enrich(result, fmax)
                results.append(result)
            except Exception as exc:
                failures += 1
                print(f"RUN_FAIL benchmark={bench['name']} core={core} error={exc}", file=sys.stderr)
                if not args.keep_going:
                    write_outputs(out_dir, results)
                    return 1

    print()
    print_table(results)
    write_outputs(out_dir, results)
    print(f"\nWrote {out_dir / 'results.json'} and {out_dir / 'results.csv'}")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
