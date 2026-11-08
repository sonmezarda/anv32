#!/usr/bin/env python3
"""Build doomgeneric for anv32 and run it on the simulation platform.

Steps:
  1. fetch doomgeneric (pinned commit) into build/third_party
  2. find picolibc: the system package, or the Debian package extracted
     locally without installing it
  3. find the shareware IWAD (--wad, or the Debian doom-wad-shareware
     package extracted locally)
  4. build sw/doom + doomgeneric into a word hex image
  5. build sim/tb/common/tb_platform.sv and run it
  6. turn the frame dump into PNGs and a video (tools/doom_frames.py)

The game runs in attract mode (title screen, then demo playback) because the
platform has no input yet.
"""
import argparse
import hashlib
import shutil
import subprocess
import sys
from pathlib import Path

import run_core_tests

DOOMGENERIC_URL = "https://github.com/ozkl/doomgeneric.git"
DOOMGENERIC_COMMIT = "e257a09527062bfb986b6e5e0780839b6cbd5b71"
WAD_MD5 = "f0cefca49926d00903cf57551d901abe"   # doom1.wad, shareware v1.9

PICOLIBC_SYSTEM = Path("/usr")
PICOLIBC_SPECS = "lib/picolibc/riscv64-unknown-elf/picolibc.specs"

# 12 MiB for code, read-only data and the IWAD, 20 MiB for data, heap, stack
LINK_SYMBOLS = {
    "__flash": 0x8000_0000,
    "__flash_size": 0x00C0_0000,
    "__ram": 0x80C0_0000,
    "__ram_size": 0x0140_0000,
    "__stack_size": 0x0001_0000,
}

DOOM_DEFINES = [
    "-DCMAP256",
    "-DDOOMGENERIC_RESX=320",
    "-DDOOMGENERIC_RESY=200",
    "-DNORMALUNIX",
    "-DLINUX",
    "-D_DEFAULT_SOURCE",
]

CORE_DEFINES = {
    "anv32im1": "ANV32_BENCH_CORE_ANV32IM1",
    "anv32im2": "ANV32_BENCH_CORE_ANV32IM2",
}


def run(cmd, cwd=None, verbose=False, **kwargs):
    if verbose:
        print("+", " ".join(str(c) for c in cmd))
    return subprocess.run([str(c) for c in cmd], cwd=cwd, check=True, **kwargs)


def apt_extract(package: str, dest: Path, verbose: bool) -> None:
    """Download a Debian package (no root needed) and unpack it into dest."""
    debs = dest.parent / "debs"
    debs.mkdir(parents=True, exist_ok=True)
    run(["apt-get", "download", package], cwd=debs, verbose=verbose)
    deb = sorted(debs.glob(f"{package}_*.deb"))[-1]
    run(["dpkg-deb", "-x", deb, dest], verbose=verbose)


def get_doomgeneric(third_party: Path, verbose: bool) -> Path:
    repo = third_party / "doomgeneric"
    if not repo.exists():
        run(["git", "clone", "-q", DOOMGENERIC_URL, repo], verbose=verbose)
    run(["git", "-C", repo, "checkout", "-q", DOOMGENERIC_COMMIT], verbose=verbose)
    return repo / "doomgeneric"


def get_picolibc(third_party: Path, verbose: bool) -> Path:
    if (PICOLIBC_SYSTEM / PICOLIBC_SPECS).exists():
        return PICOLIBC_SYSTEM
    local = third_party / "picolibc"
    if not (local / "usr" / PICOLIBC_SPECS).exists():
        print("picolibc not installed; extracting picolibc-riscv64-unknown-elf locally")
        apt_extract("picolibc-riscv64-unknown-elf", local, verbose)
    return local / "usr"


def get_wad(args, third_party: Path) -> Path:
    if args.wad:
        wad = args.wad.resolve()
    else:
        local = third_party / "wad"
        wad = local / "usr/share/games/doom/doom1.wad"
        if not wad.exists():
            print("extracting the doom-wad-shareware package locally")
            apt_extract("doom-wad-shareware", local, args.verbose)
    md5 = hashlib.md5(wad.read_bytes()).hexdigest()
    if md5 != WAD_MD5:
        print(f"warning: {wad} is not the v1.9 shareware doom1.wad (md5 {md5})")
    return wad


def doom_sources(dg: Path) -> list[Path]:
    """Object list from doomgeneric's own Makefile, minus its X11 port."""
    for line in (dg / "Makefile").read_text().splitlines():
        if line.startswith("SRC_DOOM ="):
            objs = line.split("=", 1)[1].split()
            return [dg / o.replace(".o", ".c") for o in objs if o != "doomgeneric_xlib.o"]
    raise SystemExit("SRC_DOOM not found in doomgeneric Makefile")


def build_image(args, repo: Path, dg: Path, picolibc: Path, wad: Path, out: Path) -> Path:
    obj = out / "obj"
    obj.mkdir(parents=True, exist_ok=True)
    cflags = [
        f"-march={args.march}", "-mabi=ilp32", "-O2",
        "-ffunction-sections", "-fdata-sections",
        f"-specs={picolibc / PICOLIBC_SPECS}", f"--picolibc-prefix={picolibc}",
        *DOOM_DEFINES, f"-I{dg}",
    ]
    objects = []
    for src in doom_sources(dg):
        o = obj / (src.stem + ".o")
        run([args.cc, *cflags, "-w", "-c", src, "-o", o], verbose=args.verbose)
        objects.append(o)
    for src in sorted((repo / "sw/doom").glob("*.c")):
        o = obj / (src.stem + ".o")
        run([args.cc, *cflags, "-Wall", "-c", src, "-o", o], verbose=args.verbose)
        objects.append(o)
    o = obj / "doom_wad.o"
    run([args.cc, *cflags, f"-Wa,-I{wad.parent}", "-c", repo / "sw/doom/doom_wad.S", "-o", o],
        verbose=args.verbose)
    objects.append(o)

    elf = out / "doom.elf"
    ldflags = [f"-Wl,--defsym={k}=0x{v:08x}" for k, v in LINK_SYMBOLS.items()]
    run([args.cc, *cflags, *ldflags, f"-Wl,-Map,{out / 'doom.map'}", *objects, "-o", elf],
        verbose=args.verbose)
    run([args.size, elf])
    run([args.objcopy, "-O", "binary", elf, out / "doom.bin"], verbose=args.verbose)
    run([sys.executable, repo / "tools/bin_to_hex.py", out / "doom.bin", out / "doom.hex"],
        verbose=args.verbose, stdout=subprocess.DEVNULL)
    return out / "doom.hex"


def build_sim(args, repo: Path, out: Path) -> Path:
    mdir = out / f"obj_{args.core}"
    cmd = [
        args.verilator, "-sv", "--binary", "--timing", "-Wall", "-Wno-fatal",
        *run_core_tests.QUIET_WARNINGS,
        "-O3", "--x-assign", "fast", "--x-initial", "fast", "-CFLAGS", "-O2",
        "-Mdir", mdir, "--top-module", "tb_platform", f"-D{CORE_DEFINES[args.core]}",
        *run_core_tests.CORE_SOURCES[args.core], "sim/tb/common/tb_platform.sv",
    ]
    if args.verbose:
        run(cmd, cwd=repo, verbose=True)
    else:
        # Lint warnings are noise here; show the output only if the build fails
        proc = subprocess.run([str(c) for c in cmd], cwd=repo, text=True,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        if proc.returncode != 0:
            print(proc.stdout)
            raise SystemExit("verilator build failed")
    return mdir / "Vtb_platform"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--core", choices=sorted(CORE_DEFINES), default="anv32im1")
    parser.add_argument("--wad", type=Path, help="doom1.wad (default: Debian shareware package)")
    parser.add_argument("--max-cycles", type=int, default=1_500_000_000)
    parser.add_argument("--max-frames", type=int, default=0)
    parser.add_argument("--imem-lat", type=int, default=0,
                        help="wait states before each instruction fetch is accepted")
    parser.add_argument("--dmem-lat", type=int, default=0,
                        help="wait states before each RAM load/store is accepted")
    parser.add_argument("--lat-from-frame", type=int, default=0,
                        help="turn the wait states on after this many frames")
    parser.add_argument("--window", type=int, default=0,
                        help="stop after this many instructions with the wait states on")
    parser.add_argument("--png", default="", help="frame numbers to save as PNG")
    parser.add_argument("--video", type=Path, help="write the frames as .mp4 or .gif")
    parser.add_argument("--out-dir", type=Path, default=Path("build/doom"))
    parser.add_argument("--cc", default="riscv64-unknown-elf-gcc")
    parser.add_argument("--objcopy", default="riscv64-unknown-elf-objcopy")
    parser.add_argument("--size", default="riscv64-unknown-elf-size")
    parser.add_argument("--march", default="rv32im_zicsr")
    parser.add_argument("--verilator", default="verilator")
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args()

    repo = Path(__file__).resolve().parent.parent
    third_party = repo / "build/third_party"
    third_party.mkdir(parents=True, exist_ok=True)
    out = (repo / args.out_dir).resolve()
    out.mkdir(parents=True, exist_ok=True)

    dg = get_doomgeneric(third_party, args.verbose)
    picolibc = get_picolibc(third_party, args.verbose)
    wad = get_wad(args, third_party)

    hex_file = build_image(args, repo, dg, picolibc, wad, out)
    sim = build_sim(args, repo, out)

    frames = out / f"frames_{args.core}.bin"
    log = out / f"run_{args.core}.log"
    cmd = [sim, f"+prog={hex_file}", f"+max_cycles={args.max_cycles}", f"+frames={frames}"]
    if args.max_frames:
        cmd.append(f"+max_frames={args.max_frames}")
    for name in ("imem_lat", "dmem_lat", "lat_from_frame", "window"):
        if getattr(args, name):
            cmd.append(f"+{name}={getattr(args, name)}")
    print(f"running Doom on {args.core}; console output in {log}")
    with log.open("w") as f:
        proc = subprocess.Popen([str(c) for c in cmd], cwd=out, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True)
        for line in proc.stdout:
            f.write(line)
            if not line.startswith("[platform] frame"):
                print(line, end="", flush=True)
        proc.wait()

    conv = [sys.executable, repo / "tools/doom_frames.py", frames,
            "--out-dir", out / f"frames_{args.core}"]
    if args.png:
        conv += ["--png", args.png]
    if args.video:
        if shutil.which("ffmpeg") is None:
            raise SystemExit("ffmpeg not found")
        conv += ["--video", args.video.resolve()]
    run(conv, verbose=args.verbose)


if __name__ == "__main__":
    main()
