#!/usr/bin/env python3
"""Load a program into a running anv32 board through the UART bootloader.

Usage:
    uart_load.py --port /dev/ttyUSB0 prog.bin [--monitor]
    uart_load.py --port COM5 prog.bin            (Windows)

Sends the boot trigger, which resets the SoC into the bootloader (no reset
button needed), then the image; see sw/boot/bootloader.S for the protocol.
prog.bin is the raw image starting at address 0, as `make fpga` and
`make load` build it. --monitor keeps printing what the board sends.

Needs pyserial (pip install pyserial).
"""
import argparse
import struct
import sys
import time
import zlib

import serial

TRIGGER = b"\x1bANV32BL"            # anv32_boot_trigger MAGIC
HELLO = b"anv32 boot\r\n"
REPLIES = {
    b"K": "ok",
    b"S": "bad length",
    b"E": "CRC mismatch",
    b"T": "timeout while receiving",
}


def wait_for(port, marker, timeout):
    """Read until marker shows up; return False on timeout."""
    seen = b""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        seen += port.read(max(1, port.in_waiting))
        if marker in seen:
            return True
        seen = seen[-len(marker):]
    return False


def load(port, image, retries):
    header = b"L" + struct.pack("<II", len(image), zlib.crc32(image))
    # 10 bits per byte on the wire, plus margin for the CRC check
    reply_timeout = 2.0 + len(image) * 10 / port.baudrate * 1.5
    for attempt in range(1, retries + 1):
        port.reset_input_buffer()
        port.write(TRIGGER)
        if not wait_for(port, HELLO, 2.0):
            sys.exit("no answer from the bootloader (is it in the bitstream, "
                     "and is the port right?)")
        port.write(header + image)
        port.flush()
        port.timeout = reply_timeout
        reply = port.read(1)
        port.timeout = 0.1
        status = REPLIES.get(reply, f"unexpected reply {reply!r}")
        if reply == b"K":
            return
        print(f"attempt {attempt}: {status}", file=sys.stderr)
    sys.exit("load failed")


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("image", help="raw program image (.bin) starting at 0")
    parser.add_argument("--port", required=True)
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--max-size", type=lambda s: int(s, 0), default=0x7C00,
                        help="bytes below the bootloader (default 0x7C00)")
    parser.add_argument("--retries", type=int, default=3)
    parser.add_argument("--monitor", action="store_true",
                        help="print the board's output after loading")
    args = parser.parse_args()

    with open(args.image, "rb") as f:
        image = f.read()
    image += b"\0" * (-len(image) % 4)
    if not image or len(image) > args.max_size:
        sys.exit(f"{args.image}: {len(image)} bytes; must be 1..{args.max_size}")

    with serial.Serial(args.port, args.baud, timeout=0.1) as port:
        start = time.monotonic()
        load(port, image, args.retries)
        print(f"loaded {len(image)} bytes in {time.monotonic() - start:.1f} s")
        if args.monitor:
            try:
                while True:
                    data = port.read(max(1, port.in_waiting))
                    sys.stdout.write(data.decode(errors="replace"))
                    sys.stdout.flush()
            except KeyboardInterrupt:
                pass


if __name__ == "__main__":
    main()
