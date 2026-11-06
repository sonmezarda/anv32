#!/usr/bin/env python3
"""Build and run the cross-core benchmark suite (corebench).

Every core in sim/corebench/cores.json is simulated through its adapter in
the same testbench (sim/corebench/tb_corebench.sv), running the same
binaries from sw/corebench/benchmarks.json. One Verilator model is built per
core and one program image per (benchmark, ISA, optimization level); the
simulations then run in parallel. See docs/corebench.md.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import csv
import datetime
import json
import os
import re
import shlex
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

CORES_JSON = "sim/corebench/cores.json"
BENCH_JSON = "sw/corebench/benchmarks.json"
TB = "sim/corebench/tb_corebench.sv"
COMMON = "sw/corebench/common"

# The same binary must retire the same number of instructions on every core.
# Cores count retirement at different pipeline stages relative to the ROI
# marker stores, so allow a few instructions of skew at the ROI edges.
INSTRET_SKEW = 16

RESULT_RE = re.compile(r"^COREBENCH_RESULT\s+(?P<body>.*)$", re.M)
PROBE_RE = re.compile(r"^COREBENCH_PROBE\s+(?P<body>.*)$", re.M)
COREMARK_10S_ERROR = "ERROR! Must execute for at least 10 secs for a valid result!"


@dataclass
class Program:
    bench: str
    isa: str
    opt: str
    dir: Path
    hex: Path | None = None
    size: dict = field(default_factory=dict)
    error: str | None = None


def run(cmd: list[str], *, cwd: Path, log: Path | None = None, verbose: bool = False) -> str:
    if verbose:
        print("+ " + shlex.join(cmd), flush=True)
    proc = subprocess.run(cmd, cwd=cwd, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if log is not None:
        with log.open("a") as f:
            f.write("+ " + shlex.join(cmd) + "\n" + proc.stdout)
    if proc.returncode != 0:
        raise RuntimeError(f"command failed ({proc.returncode}): {shlex.join(cmd)}\n{proc.stdout[-4000:]}")
    return proc.stdout


def split_list(value: str) -> list[str]:
    return [item.strip() for item in value.split(",") if item.strip()]


def isa_extensions(isa: str) -> set[str]:
    match = re.fullmatch(r"rv32([a-z]+)", isa)
    if not match:
        raise SystemExit(f"bad ISA '{isa}', expected e.g. rv32im")
    return set(match.group(1))


def tool_version(cmd: list[str]) -> str:
    try:
        return subprocess.run(cmd, text=True, capture_output=True).stdout.splitlines()[0].strip()
    except (OSError, IndexError):
        return "unknown"


def git_describe(path: Path) -> str:
    out = subprocess.run(["git", "-C", str(path), "describe", "--always", "--dirty"],
                         text=True, capture_output=True)
    return out.stdout.strip() or "unknown"


# ---- Program build ---------------------------------------------------------

def build_program(args: argparse.Namespace, repo: Path, name: str, bench: dict, prog: Program) -> Program:
    prog.dir.mkdir(parents=True, exist_ok=True)
    log = prog.dir / "build.log"
    log.write_text("")
    march = f"{prog.isa}_zicsr"
    iterations = args.iterations or bench.get("iterations")

    cflags = [
        f"-march={march}", "-mabi=ilp32", prog.opt,
        "-ffreestanding", "-fno-pic", "-fno-pie",
        "-ffunction-sections", "-fdata-sections",
        "-msmall-data-limit=0",
    ]
    flags_str = " ".join(cflags)
    defines = [f'-DFLAGS_STR="{flags_str}"']
    if iterations and bench.get("iterations_define"):
        defines.append(f"-D{bench['iterations_define']}={iterations}")
    for key, value in bench.get("defines", {}).items():
        defines.append(f"-D{key}={value}")
    includes = [f"-I{d}" for d in [COMMON, *bench.get("include_dirs", [])]]

    sources = [f"{COMMON}/crt0.S", f"{COMMON}/libc.c", *bench["sources"]]
    objects = []
    try:
        for i, src in enumerate(sources):
            obj = prog.dir / f"{i:02d}_{Path(src).stem}.o"  # sources may share a stem
            run([args.cc, *cflags, *defines, *includes, "-c", src, "-o", str(obj)], cwd=repo, log=log)
            objects.append(str(obj))

        elf = prog.dir / f"{name}.elf"
        run([args.cc, *cflags, "-nostdlib", "-nostartfiles", "-T", f"{COMMON}/link.ld",
             "-Wl,--gc-sections", "-Wl,--no-relax", "-Wl,--no-warn-rwx-segments",
             f"-Wl,-Map={prog.dir / (name + '.map')}", *objects, "-lgcc", "-o", str(elf)],
            cwd=repo, log=log)
        binary = prog.dir / f"{name}.bin"
        run([args.objcopy, "-O", "binary", str(elf), str(binary)], cwd=repo, log=log)
        prog.hex = prog.dir / f"{name}.hex"
        run([sys.executable, "tools/bin_to_hex.py", str(binary), str(prog.hex)], cwd=repo, log=log)
        (prog.dir / f"{name}.dump").write_text(
            run([args.objdump, "-d", "-M", "no-aliases", str(elf)], cwd=repo))
        size_line = run([args.size, str(elf)], cwd=repo).splitlines()[1].split()
        prog.size = {"text": int(size_line[0]), "data": int(size_line[1]), "bss": int(size_line[2])}
    except RuntimeError:
        prog.error = f"program build failed, see {log}"
    return prog


# ---- Verilator models ------------------------------------------------------

def build_model(args: argparse.Namespace, repo: Path, core: str, spec: dict, out_dir: Path) -> Path:
    mdir = out_dir / "models" / core
    mdir.mkdir(parents=True, exist_ok=True)
    log = mdir / "build.log"
    log.write_text("")
    cmd = [
        args.verilator, "-sv", "--binary", "--timing",
        "-Wno-fatal", "-Wno-lint", "-Wno-style",
        "-DCOREBENCH_SIM",
        "--top-module", "tb_corebench",
        "-Mdir", str(mdir), "-o", "Vtb_corebench",
        # Multithreaded verilation sometimes aborts on Verilator 5.020 ("attempted
        # to destroy locked Thread Pool"); only the C++ build runs in parallel.
        "--verilate-jobs", "1", "--build-jobs", str(max(1, args.jobs // 2)),
        *[f"+incdir+{d}" for d in spec.get("include_dirs", [])],
        *spec.get("verilator_flags", []),
        *spec["sources"], spec["adapter"],
        *(["-DCOREBENCH_PROBE", spec["probe"]] if spec.get("probe") else []),
        TB,
    ]
    run(cmd, cwd=repo, log=log, verbose=args.verbose)
    return mdir / "Vtb_corebench"


# ---- Simulation and checks -------------------------------------------------

def parse_fields(body: str) -> dict:
    values: dict[str, object] = {}
    for token in body.split():
        key, value = token.split("=", 1)
        values[key] = int(value, 16) if value.startswith("0x") else int(value) if value.isdigit() else value
    return values


def parse_result(text: str) -> dict:
    match = RESULT_RE.search(text)
    if not match:
        raise RuntimeError("simulation ended without COREBENCH_RESULT")
    values = parse_fields(match.group("body"))
    probe = PROBE_RE.search(text)
    if probe:
        values["probe"] = parse_fields(probe.group("body"))
    return values


def check_coremark(console: str, iterations: int | None) -> str | None:
    errors = [line.strip() for line in console.splitlines()
              if "ERROR" in line and line.strip() != COREMARK_10S_ERROR]
    if errors:
        return "; ".join(errors)
    if "crcfinal" not in console:
        return "CoreMark did not print its results"
    match = re.search(r"^Iterations\s*:\s*(\d+)", console, re.M)
    if iterations and (not match or int(match.group(1)) != iterations):
        return f"CoreMark ran {match.group(1) if match else '?'} iterations, expected {iterations}"
    return None


def run_one(args: argparse.Namespace, repo: Path, core: str, model: Path, name: str,
            bench: dict, prog: Program, out_dir: Path) -> dict:
    result = {
        "benchmark": name, "core": core, "isa": prog.isa, "opt": prog.opt,
        "code_bytes": prog.size.get("text"),
    }
    if prog.error:
        return {**result, "status": "FAIL", "error": prog.error}

    run_dir = out_dir / "runs" / f"{name}_{prog.isa}_{prog.opt.lstrip('-')}" / core
    run_dir.mkdir(parents=True, exist_ok=True)
    console = run_dir / "console.log"
    sim_log = run_dir / "sim.log"
    max_cycles = args.max_cycles or bench.get("max_cycles", 100_000_000)
    proc = subprocess.run([str(model), f"+image={prog.hex}", f"+max_cycles={max_cycles}",
                           f"+console={console}"],
                          cwd=repo, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    sim_log.write_text(proc.stdout)
    try:
        sim = parse_result(proc.stdout)
    except RuntimeError:
        # $fatal from the testbench (bus error) or the model itself
        reason = next((line.strip() for line in proc.stdout.splitlines()
                       if "corebench:" in line or line.startswith("%Error")),
                      f"simulator exited with {proc.returncode}")
        return {**result, "status": "FAIL", "error": f"{reason} (see {sim_log})"}

    result.update(sim)
    result["cpi"] = sim["roi_cycles"] / sim["roi_instret"] if sim["roi_instret"] else None

    error = None
    if sim["status"] == "trap":
        error = f"trap mcause=0x{sim['trap_cause']:08x} mepc=0x{sim['trap_epc']:08x}"
    elif sim["status"] != "exit":
        error = f"{sim['status']} after {sim['cycles']} cycles"
    elif sim["exit_code"] != bench.get("expect_exit", 0):
        error = f"exit code {sim['exit_code']}, expected {bench.get('expect_exit', 0)}"
    elif bench.get("check") == "coremark":
        error = check_coremark(console.read_text(errors="replace"), args.iterations or bench.get("iterations"))
    result["status"] = "FAIL" if error else "PASS"
    if error:
        result["error"] = error

    iterations = args.iterations or bench.get("iterations")
    if bench.get("metric") and iterations and not error:
        result["metric"] = bench["metric"]
        result["score_per_mhz"] = iterations * 1e6 / sim["roi_cycles"]
    return result


def check_instret(results: list[dict]) -> list[str]:
    """Same binary, same instruction count: flags adapters that miscount."""
    groups: dict[tuple, list[dict]] = {}
    for r in results:
        if r["status"] == "PASS":
            groups.setdefault((r["benchmark"], r["isa"], r["opt"]), []).append(r)
    warnings = []
    for (bench, isa, opt), rows in groups.items():
        counts = [r["roi_instret"] for r in rows]
        if max(counts) - min(counts) > INSTRET_SKEW:
            detail = ", ".join(f"{r['core']}={r['roi_instret']}" for r in rows)
            warnings.append(f"instret mismatch for {bench} ({isa} {opt}): {detail}")
    return warnings


# ---- Fmax ------------------------------------------------------------------

def load_fmax(args: argparse.Namespace) -> dict[str, dict[str, float]]:
    """Returns {core: {target: MHz}} from fpga_eval summaries and --fmax."""
    fmax: dict[str, dict[str, float]] = {}
    for path in args.fmax_json or []:
        for row in json.loads(Path(path).read_text()):
            if row.get("fmax_mhz"):
                fmax.setdefault(row["core"], {})[row["target"]] = float(row["fmax_mhz"])
    for item in args.fmax or []:
        for chunk in split_list(item):
            core_target, _, mhz = chunk.partition("=")
            core, _, target = core_target.partition("@")
            if not mhz:
                raise SystemExit(f"bad --fmax item '{chunk}', expected core@target=MHz")
            fmax.setdefault(core, {})[target or "fmax"] = float(mhz)
    return fmax


def apply_fmax(results: list[dict], fmax: dict[str, dict[str, float]]) -> list[str]:
    targets = sorted({t for per_core in fmax.values() for t in per_core})
    for r in results:
        for target in targets:
            mhz = fmax.get(r["core"], {}).get(target)
            if mhz is None or r["status"] != "PASS":
                continue
            r[f"fmax_mhz@{target}"] = mhz
            r[f"time_us@{target}"] = r["roi_cycles"] / mhz
            if "score_per_mhz" in r:
                r[f"score@{target}"] = r["score_per_mhz"] * mhz
    return targets


# ---- Output ----------------------------------------------------------------

def fmt(value: object, digits: int = 3) -> str:
    if value is None or value == "":
        return "-"
    if isinstance(value, float):
        return f"{value:.{digits}f}"
    return str(value)


def table_rows(results: list[dict], targets: list[str]) -> tuple[list[str], list[list[str]]]:
    headers = ["benchmark", "core", "isa", "status", "code B", "ROI cycles", "ROI instret", "CPI", "score/MHz"]
    for target in targets:
        headers += [f"MHz@{target}", f"score/us@{target}"]
    rows = []
    for r in results:
        row = [r["benchmark"], r["core"], r["isa"], r["status"], fmt(r.get("code_bytes")),
               fmt(r.get("roi_cycles")), fmt(r.get("roi_instret")), fmt(r.get("cpi")),
               fmt(r.get("score_per_mhz"))]
        for target in targets:
            row.append(fmt(r.get(f"fmax_mhz@{target}"), 2))
            if "score_per_mhz" in r:
                row.append(fmt(r.get(f"score@{target}"), 2))
            else:
                row.append(fmt(r.get(f"time_us@{target}"), 1))
        rows.append(row)
    return headers, rows


def print_table(headers: list[str], rows: list[list[str]]) -> None:
    widths = [max([len(h)] + [len(row[i]) for row in rows]) for i, h in enumerate(headers)]
    print("  ".join(h.ljust(w) for h, w in zip(headers, widths)))
    print("  ".join("-" * w for w in widths))
    for row in rows:
        print("  ".join(cell.ljust(w) for cell, w in zip(row, widths)))


def write_outputs(out_dir: Path, results: list[dict], meta: dict, headers: list[str],
                  rows: list[list[str]]) -> None:
    (out_dir / "results.json").write_text(json.dumps({"meta": meta, "results": results}, indent=2) + "\n")

    flat = [{**{k: v for k, v in r.items() if k != "probe"},
             **{f"probe.{k}": v for k, v in r.get("probe", {}).items()}} for r in results]
    fields: list[str] = []
    for r in flat:
        fields += [k for k in r if k not in fields]
    with (out_dir / "results.csv").open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        writer.writerows(flat)

    lines = ["| " + " | ".join(headers) + " |",
             "| " + " | ".join("---" if i < 4 else "---:" for i in range(len(headers))) + " |"]
    lines += ["| " + " | ".join(row) + " |" for row in rows]
    (out_dir / "results.md").write_text("\n".join(lines) + "\n")


# ---- Main ------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--cores", default="all", help="comma-separated core names (default: all)")
    parser.add_argument("--benchmarks", default="all", help="comma-separated benchmark names or tags")
    parser.add_argument("--isa", default="native",
                        help="comma-separated ISAs to build for, e.g. rv32im,rv32imc; 'native' "
                             "uses each core's own ISA. Cores skip ISAs they do not support.")
    parser.add_argument("--opt", default="-O2", help="optimization level (default: -O2)")
    parser.add_argument("--iterations", type=int, help="override CoreMark-style iteration counts")
    parser.add_argument("--max-cycles", type=int, help="override per-benchmark timeouts")
    parser.add_argument("--bench-list", default=BENCH_JSON,
                        help=f"benchmark manifest (default: {BENCH_JSON})")
    parser.add_argument("--out-dir", default="build/corebench")
    parser.add_argument("--jobs", type=int, default=os.cpu_count() or 4)
    parser.add_argument("--fmax-json", action="append",
                        help="fpga_eval summary.json to read Fmax from (repeatable)")
    parser.add_argument("--fmax", action="append", help="core@target=MHz, comma separated")
    parser.add_argument("--verilator", default="verilator")
    parser.add_argument("--cc", default="riscv64-unknown-elf-gcc")
    parser.add_argument("--objcopy", default="riscv64-unknown-elf-objcopy")
    parser.add_argument("--objdump", default="riscv64-unknown-elf-objdump")
    parser.add_argument("--size", default="riscv64-unknown-elf-size")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    repo = Path(__file__).resolve().parent.parent
    out_dir = Path(args.out_dir).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    all_cores = json.loads((repo / CORES_JSON).read_text())
    all_benches = json.loads((repo / args.bench_list).read_text())

    cores = list(all_cores) if args.cores == "all" else split_list(args.cores)
    unknown = sorted(set(cores) - set(all_cores))
    if unknown:
        raise SystemExit(f"unknown core(s): {', '.join(unknown)}; see {CORES_JSON}")

    if args.benchmarks == "all":
        benches = list(all_benches)
    else:
        wanted = set(split_list(args.benchmarks))
        benches = [n for n, b in all_benches.items() if n in wanted or wanted & set(b.get("tags", []))]
        known = set(all_benches).union(*(b.get("tags", []) for b in all_benches.values()))
        if wanted - known:
            raise SystemExit(f"unknown benchmark/tag(s): {', '.join(sorted(wanted - known))}")

    # (core, benchmark, isa) runs, skipping ISAs a core does not implement
    plan: list[tuple[str, str, str]] = []
    for name in benches:
        for core in cores:
            core_isa = all_cores[core]["isa"]
            for isa in split_list(args.isa):
                isa = core_isa if isa == "native" else isa
                if isa_extensions(isa) <= isa_extensions(core_isa) and (core, name, isa) not in plan:
                    plan.append((core, name, isa))
    if not plan:
        raise SystemExit("nothing to run: no selected core supports the selected ISA(s)")

    programs = {(n, isa): Program(n, isa, args.opt, out_dir / "programs" / n / f"{isa}_{args.opt.lstrip('-')}")
                for _, n, isa in plan}
    with concurrent.futures.ThreadPoolExecutor(args.jobs) as pool:
        print(f"Building {len(programs)} program image(s) and {len({c for c, _, _ in plan})} core model(s)",
              flush=True)
        prog_futs = [pool.submit(build_program, args, repo, p.bench, all_benches[p.bench], p)
                     for p in programs.values()]
        model_futs = {core: pool.submit(build_model, args, repo, core, all_cores[core], out_dir)
                      for core in dict.fromkeys(c for c, _, _ in plan)}
        for fut in prog_futs:
            prog = fut.result()
            if prog.error:
                print(f"BUILD_FAIL {prog.bench} {prog.isa}: see {prog.dir / 'build.log'}", file=sys.stderr)
        models: dict[str, Path | None] = {}
        for core, fut in model_futs.items():
            try:
                models[core] = fut.result()
            except RuntimeError:
                models[core] = None
                print(f"MODEL_FAIL {core}: see {out_dir / 'models' / core / 'build.log'}", file=sys.stderr)

        print(f"Running {len(plan)} simulation(s)", flush=True)
        run_futs = []
        for core, name, isa in plan:
            if models[core] is None:
                continue
            run_futs.append(pool.submit(run_one, args, repo, core, models[core], name,
                                        all_benches[name], programs[(name, isa)], out_dir))
        results = []
        for fut in concurrent.futures.as_completed(run_futs):
            r = fut.result()
            results.append(r)
            line = f"{r['status']} {r['benchmark']} {r['core']} {r['isa']}"
            print(line + (f": {r['error']}" if "error" in r else ""), flush=True)

    order = {key: i for i, key in enumerate(plan)}
    results.sort(key=lambda r: order[(r["core"], r["benchmark"], r["isa"])])
    results.sort(key=lambda r: benches.index(r["benchmark"]))

    targets = apply_fmax(results, load_fmax(args))
    warnings = check_instret(results)
    meta = {
        "date": datetime.datetime.now().isoformat(timespec="seconds"),
        "repo": git_describe(repo),
        "third_party": {d.name: git_describe(d) for d in sorted((repo / "third_party").iterdir())
                        if (d / ".git").exists()},
        "cc": tool_version([args.cc, "--version"]),
        "verilator": tool_version([args.verilator, "--version"]),
        "opt": args.opt,
        "fmax_targets": targets,
    }
    headers, rows = table_rows(results, targets)
    print()
    print_table(headers, rows)
    probed = [r for r in results if "probe" in r]
    if probed:
        keys = ["redirects", "branches", "branches_taken", "loads", "load_use_stall_cycles",
                "muldiv_stall_cycles"]
        print("\nCore probes (inside the ROI)")
        print_table(["benchmark", "core", "isa", "lost cycles", *keys],
                    [[r["benchmark"], r["core"], r["isa"], fmt(r["roi_cycles"] - r["roi_instret"]),
                      *(fmt(r["probe"].get(k)) for k in keys)] for r in probed])
    write_outputs(out_dir, results, meta, headers, rows)
    for warning in warnings:
        print(f"WARNING: {warning}", file=sys.stderr)
    print(f"\nWrote {out_dir}/results.{{json,csv,md}}")

    failed = sum(r["status"] != "PASS" for r in results) + (len(plan) - len(results))
    return 1 if failed or warnings else 0


if __name__ == "__main__":
    raise SystemExit(main())
