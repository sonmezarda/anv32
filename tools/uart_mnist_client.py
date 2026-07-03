#!/usr/bin/env python3
"""Talk to the ANV32 MNIST accelerator over UART.

The model (weights + biases) is uploaded once with --load-model; after that
each run only sends the 196-word image packet and reads the response.
"""

from __future__ import annotations

import argparse
import os
import subprocess
import struct
import sys
import time
from pathlib import Path

import numpy as np

try:
    import serial
except ImportError as exc:  # pragma: no cover - user environment hint
    raise SystemExit("pyserial is required: python3 -m pip install pyserial") from exc

from generate_mnist_demo import (
    INPUT_WORDS,
    MNIST_URLS,
    OUTPUTS,
    build_centroid_model,
    choose_sample,
    download,
    pack_i8x4,
    quantize_images,
    read_idx_images,
    read_idx_labels,
    scores_for,
)


MODEL_WORDS = OUTPUTS * INPUT_WORDS + OUTPUTS
READY_LINE = b"ANV32_NN_UART_READY\n"
BOARD_CLK_HZ = 27_000_000

STATUS_NAMES = {
    0: "OK",
    1: "bad magic",
    2: "bad word count",
    3: "checksum mismatch",
    4: "accelerator error",
    5: "no model loaded (run with --load-model first)",
}


def load_mnist(data_dir: Path) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    paths = {name: data_dir / Path(url).name for name, url in MNIST_URLS.items()}

    for name, url in MNIST_URLS.items():
        download(url, paths[name])

    train_x = read_idx_images(paths["train_images"])
    train_y = read_idx_labels(paths["train_labels"])
    test_x = read_idx_images(paths["test_images"])
    test_y = read_idx_labels(paths["test_labels"])

    return train_x, train_y, test_x, test_y


def make_packet(magic: bytes, words: list[int]) -> bytes:
    payload = b"".join(struct.pack("<I", word & 0xFFFF_FFFF) for word in words)
    checksum = sum(payload) & 0xFFFF_FFFF

    return magic + struct.pack("<HI", len(words), checksum) + payload


def build_model_packet(weights: np.ndarray, biases: np.ndarray) -> bytes:
    words = []

    for cls in range(OUTPUTS):
        for word_index in range(INPUT_WORDS):
            lo = word_index * 4
            words.append(pack_i8x4(weights[cls, lo : lo + 4]))

    for cls in range(OUTPUTS):
        words.append(int(biases[cls]) & 0xFFFF_FFFF)

    assert len(words) == MODEL_WORDS
    return make_packet(b"NNM1", words)


def build_image_packet(image_q: np.ndarray) -> bytes:
    words = []

    for word_index in range(INPUT_WORDS):
        lo = word_index * 4
        words.append(pack_i8x4(image_q[lo : lo + 4]))

    return make_packet(b"NNI1", words)


def scan_magic(port: serial.Serial, magic: bytes) -> None:
    # Scan for the magic so stray bytes on the line are skipped instead of
    # aborting the run.
    window = b""
    while window != magic:
        byte = port.read(1)
        if not byte:
            raise TimeoutError(f"serial timeout waiting for {magic!r}")
        window = (window + byte)[-4:]


def read_exact(port: serial.Serial, size: int) -> bytes:
    data = port.read(size)
    if len(data) != size:
        raise TimeoutError(f"serial timeout: expected {size} bytes, got {len(data)}")
    return data


def read_model_ack(port: serial.Serial) -> int:
    scan_magic(port, b"NNA1")
    status = read_exact(port, 1)[0]
    _reserved = read_exact(port, 3)
    return status


def read_response(port: serial.Serial) -> tuple[int, int, int, int, list[int]]:
    scan_magic(port, b"NNR1")

    status = read_exact(port, 1)[0]
    pred = read_exact(port, 1)[0]
    _reserved = read_exact(port, 2)
    best_score = struct.unpack("<i", read_exact(port, 4))[0]
    accel_cycles = struct.unpack("<I", read_exact(port, 4))[0]
    scores = [struct.unpack("<i", read_exact(port, 4))[0] for _ in range(OUTPUTS)]

    return status, pred, best_score, accel_cycles, scores


def wait_ready(port: serial.Serial, timeout_s: float) -> bool:
    deadline = time.monotonic() + timeout_s
    buffer = bytearray()

    while time.monotonic() < deadline:
        chunk = port.read(1)
        if not chunk:
            continue
        buffer += chunk
        if buffer.endswith(READY_LINE):
            return True
        if len(buffer) > 128:
            del buffer[:-128]

    return False


def status_message(status: int) -> str:
    return STATUS_NAMES.get(status, f"unknown status {status}")


ASCII_RAMP = " .:-=+*#%@"


def image_to_ascii(image: np.ndarray) -> str:
    pixels = image.reshape(28, 28)
    lines = []
    for row in pixels:
        line = "".join(ASCII_RAMP[min(int(p) * len(ASCII_RAMP) // 256,
                                      len(ASCII_RAMP) - 1)] * 2 for p in row)
        lines.append(line)
    return "\n".join(lines)


def write_png(path: Path, image: np.ndarray, scale: int = 8) -> None:
    """Write a grayscale PNG using only the standard library."""
    import zlib

    img = np.kron(image.reshape(28, 28).astype(np.uint8),
                  np.ones((scale, scale), dtype=np.uint8))
    height, width = img.shape
    raw = b"".join(b"\x00" + img[row].tobytes() for row in range(height))

    def chunk(tag: bytes, data: bytes) -> bytes:
        out = struct.pack(">I", len(data)) + tag + data
        return out + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFF_FFFF)

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 0, 0, 0, 0)
    path.write_bytes(b"\x89PNG\r\n\x1a\n"
                     + chunk(b"IHDR", ihdr)
                     + chunk(b"IDAT", zlib.compress(raw))
                     + chunk(b"IEND", b""))


def open_image(path: Path) -> None:
    if sys.platform.startswith("win"):
        os.startfile(path)  # type: ignore[attr-defined]
    elif sys.platform == "darwin":
        subprocess.Popen(["open", str(path)])
    else:
        opener = "wslview" if "microsoft" in Path("/proc/version").read_text(
            errors="ignore"
        ).lower() else "xdg-open"
        subprocess.Popen([opener, str(path)])


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", default="/dev/ttyUSB0")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--clock-hz", type=int, default=BOARD_CLK_HZ,
                        help="accelerator clock used to convert cycles to time")
    parser.add_argument("--data-dir", type=Path, default=Path("data/mnist"))
    parser.add_argument("--index", type=int, default=None, help="MNIST test image index")
    parser.add_argument("--timeout", type=float, default=10.0)
    parser.add_argument("--ready-timeout", type=float, default=2.0)
    parser.add_argument("--no-wait-ready", action="store_true")
    parser.add_argument("--toggle-dtr", action="store_true")
    parser.add_argument("--load-model", action="store_true",
                        help="upload the model before sending the image")
    parser.add_argument("--model-only", action="store_true",
                        help="upload the model and exit without sending an image")
    parser.add_argument("--show-image", action="store_true",
                        help="print the selected MNIST image as terminal ASCII")
    parser.add_argument("--save-image", type=Path, default=None,
                        help="write the selected MNIST image to a PNG file")
    parser.add_argument("--open-image", action="store_true",
                        help="open the selected MNIST image as a PNG")
    parser.add_argument("--image-scale", type=int, default=8,
                        help="PNG pixel scale for --save-image")
    parser.add_argument("--image-only", action="store_true",
                        help="show/save/open the selected image and exit without UART")
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    if args.clock_hz <= 0:
        raise SystemExit("--clock-hz must be positive")
    if args.image_scale <= 0:
        raise SystemExit("--image-scale must be positive")

    train_x, train_y, test_x, test_y = load_mnist(args.data_dir)
    train_x_q = quantize_images(train_x)
    test_x_q = quantize_images(test_x)
    weights, biases = build_centroid_model(train_x_q, train_y)

    send_model = args.load_model or args.model_only

    if args.model_only:
        image_packet = None
        expected_pred = None
        expected_scores = None
        label = None
    else:
        if args.index is None:
            index = choose_sample(test_x_q, test_y, weights, biases)
        else:
            index = args.index
            if index < 0 or index >= len(test_x_q):
                raise SystemExit(f"--index must be in 0..{len(test_x_q) - 1}")

        image_q = test_x_q[index]
        expected_scores = [int(x) for x in
                           scores_for(image_q.reshape(1, 784), weights, biases)[0].tolist()]
        expected_pred = int(np.argmax(expected_scores))
        label = int(test_y[index])
        image_packet = build_image_packet(image_q)

        print(f"MNIST test index : {index}")
        print(f"Label            : {label}")
        print(f"Python prediction: {expected_pred}")
        print(f"Image packet     : {len(image_packet)} bytes")

        if args.show_image:
            print("Image:")
            print(image_to_ascii(test_x[index]))

        image_path = args.save_image
        if args.open_image and image_path is None:
            image_path = Path("build") / f"mnist_{index}.png"

        if image_path is not None:
            image_path.parent.mkdir(parents=True, exist_ok=True)
            write_png(image_path, test_x[index], args.image_scale)
            print(f"Image PNG        : {image_path}")

        if args.open_image and image_path is not None:
            open_image(image_path)
            print("Image open       : requested")

        if args.image_only:
            print("UART             : skipped (--image-only)")
            return

    with serial.Serial(args.port, args.baud, timeout=args.timeout) as port:
        if args.toggle_dtr:
            port.dtr = False
            time.sleep(0.1)
            port.dtr = True
            time.sleep(0.5)

        port.reset_input_buffer()
        port.reset_output_buffer()

        if not args.no_wait_ready and send_model:
            if wait_ready(port, args.ready_timeout):
                print("Board ready      : yes")
            else:
                print("Board ready      : not seen, sending anyway")

        if send_model:
            model_packet = build_model_packet(weights, biases)
            start = time.monotonic()
            port.write(model_packet)
            port.flush()
            ack = read_model_ack(port)
            model_elapsed = time.monotonic() - start

            print(f"Model packet     : {len(model_packet)} bytes")
            print(f"Model load       : status {ack} ({status_message(ack)}), "
                  f"{model_elapsed:.3f} s")

            if ack != 0:
                raise SystemExit(ack)
        else:
            print("Model packet     : skipped (using model already loaded on board)")

        if image_packet is None:
            return

        start = time.monotonic()
        print(f"Image transmit   : sending {len(image_packet)} bytes")
        port.write(image_packet)
        port.flush()
        status, pred, best_score, accel_cycles, scores = read_response(port)
        elapsed = time.monotonic() - start

    accel_us = accel_cycles * 1_000_000.0 / args.clock_hz

    print(f"HW status        : {status} ({status_message(status)})")
    print(f"HW prediction    : {pred}")
    print(f"HW best score    : {best_score}")
    print(f"Accelerator      : {accel_cycles} cycles ({accel_us:.3f} us)")
    print(f"UART round trip  : {elapsed:.3f} s")
    print(f"HW scores        : {scores}")
    print(f"Python scores    : {expected_scores}")

    if status != 0:
        raise SystemExit(status)

    if pred != expected_pred or scores != expected_scores:
        raise SystemExit("hardware result does not match Python reference")

    print("Result           : PASS")


if __name__ == "__main__":
    sys.exit(main())
