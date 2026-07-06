#!/usr/bin/env python3
"""Build a tiny freestanding RV32 C program and emit sim memory images."""

import argparse
import subprocess
from pathlib import Path


def run(cmd, stdout=None):
    shown = " ".join(str(x) for x in cmd)
    print(f"+ {shown}", flush=True)
    subprocess.run(cmd, check=True, stdout=stdout)


def object_name_for(path: Path) -> str:
    stem = "_".join(path.with_suffix("").parts)
    return f"{stem}.o"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--src", required=True, help="C source file")
    parser.add_argument("--out-dir", required=True, help="artifact directory")
    parser.add_argument("--name", required=True, help="artifact base name")
    parser.add_argument("--crt0", default="sw/common/crt0.S")
    parser.add_argument("--linker", default="sw/common/link.ld")
    parser.add_argument("--cc", default="riscv64-unknown-elf-gcc")
    parser.add_argument("--march", default="rv32i_zicsr")
    parser.add_argument("--mabi", default="ilp32")
    parser.add_argument("--objcopy", default="riscv64-unknown-elf-objcopy")
    parser.add_argument("--objdump", default="riscv64-unknown-elf-objdump")
    parser.add_argument("--bin-to-hex", default="tools/bin_to_hex.py")
    parser.add_argument("--split-hex", default="tools/split_hex.py")
    parser.add_argument("--python", default="python3")
    parser.add_argument("--opt", default="-Os")
    parser.add_argument("--lib-dir", default="sw/fpga/lib")
    args = parser.parse_args()

    src = Path(args.src)
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    base = out_dir / args.name
    c_asm = base.with_suffix(".s")
    c_obj = out_dir / f"{args.name}.o"
    crt_obj = out_dir / "crt0.o"
    lib_dir = Path(args.lib_dir)
    elf = base.with_suffix(".elf")
    binary = base.with_suffix(".bin")
    word_hex = base.with_suffix(".hex")
    dump = base.with_suffix(".dump")
    map_file = base.with_suffix(".map")

    common_flags = [
        f"-march={args.march}",
        f"-mabi={args.mabi}",
        args.opt,
        "-ffreestanding",
        "-fno-builtin",
        "-fno-pic",
        "-fno-pie",
        "-fdata-sections",
        "-ffunction-sections",
        "-msmall-data-limit=0",
        "-I",
        "sw/include",
        "-I",
        "sw/fpga",
    ]

    lib_sources = []
    if lib_dir.is_dir():
        lib_sources = sorted(
            path for path in lib_dir.glob("*.c") if path.resolve() != src.resolve()
        )
    lib_objects = [out_dir / object_name_for(path) for path in lib_sources]

    run([args.cc, *common_flags, "-S", str(src), "-o", str(c_asm)])
    run([args.cc, *common_flags, "-c", str(c_asm), "-o", str(c_obj)])
    for lib_src, lib_obj in zip(lib_sources, lib_objects):
        run([args.cc, *common_flags, "-c", str(lib_src), "-o", str(lib_obj)])
    run([args.cc, *common_flags, "-c", args.crt0, "-o", str(crt_obj)])
    run([
        args.cc,
        *common_flags,
        "-nostdlib",
        "-nostartfiles",
        str(crt_obj),
        str(c_obj),
        *[str(obj) for obj in lib_objects],
        "-T",
        args.linker,
        "-Wl,--no-relax",
        "-Wl,--gc-sections",
        "-Wl,--no-warn-rwx-segments",
        f"-Wl,-Map={map_file}",
        "-lgcc",
        "-o",
        str(elf),
    ])
    run([args.objcopy, "-O", "binary", str(elf), str(binary)])
    run([args.python, args.bin_to_hex, str(binary), str(word_hex)])
    run([args.python, args.split_hex, str(word_hex), str(base)])
    with dump.open("w") as f:
        run([args.objdump, "-d", "-M", "no-aliases", str(elf)], stdout=f)

    print(f"artifacts -> {out_dir}", flush=True)


if __name__ == "__main__":
    main()
