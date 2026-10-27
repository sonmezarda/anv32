#!/usr/bin/env python3
"""Turn the frame dump of sim/tb/common/tb_platform.sv into images.

Each frame in the dump is a 256-entry palette (b, g, r, unused) followed by
a 320x200 8-bit indexed picture.
"""
import argparse
import subprocess
from pathlib import Path

from PIL import Image

WIDTH = 320
HEIGHT = 200
PALETTE_BYTES = 256 * 4
FRAME_BYTES = PALETTE_BYTES + WIDTH * HEIGHT


def read_frames(path: Path):
    data = path.read_bytes()
    for off in range(0, len(data) - FRAME_BYTES + 1, FRAME_BYTES):
        pal = data[off:off + PALETTE_BYTES]
        rgb = bytearray()
        for i in range(256):
            b, g, r = pal[4 * i], pal[4 * i + 1], pal[4 * i + 2]
            rgb += bytes((r, g, b))
        img = Image.frombytes("P", (WIDTH, HEIGHT), data[off + PALETTE_BYTES:off + FRAME_BYTES])
        img.putpalette(bytes(rgb))
        yield img.convert("RGB")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("frames", type=Path, help="frame dump from tb_platform")
    parser.add_argument("--out-dir", type=Path, default=Path("build/doom/frames"))
    parser.add_argument("--scale", type=int, default=2)
    parser.add_argument("--png", default="", help="frame numbers to save as PNG, e.g. 0,100,250")
    parser.add_argument("--video", type=Path, help="write all frames as a video (.mp4 or .gif) with ffmpeg")
    parser.add_argument("--fps", type=int, default=35)
    args = parser.parse_args()

    args.out_dir.mkdir(parents=True, exist_ok=True)
    keep = {int(n) for n in args.png.split(",") if n}
    size = (WIDTH * args.scale, HEIGHT * args.scale)
    count = 0
    for n, img in enumerate(read_frames(args.frames)):
        img = img.resize(size, Image.NEAREST)
        if args.video:
            img.save(args.out_dir / f"frame_{n:05d}.png")
        if n in keep:
            img.save(args.out_dir / f"doom_{n:05d}.png")
        count = n + 1
    print(f"{count} frames in {args.frames}")

    if args.video and count:
        cmd = ["ffmpeg", "-y", "-loglevel", "error", "-framerate", str(args.fps),
               "-i", str(args.out_dir / "frame_%05d.png")]
        if args.video.suffix == ".gif":
            cmd += ["-vf", "split[a][b];[a]palettegen[p];[b][p]paletteuse"]
        else:
            cmd += ["-c:v", "libx264", "-pix_fmt", "yuv420p"]
        subprocess.run(cmd + [str(args.video)], check=True)
        print(f"wrote {args.video}")


if __name__ == "__main__":
    main()
