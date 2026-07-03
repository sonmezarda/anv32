#!/usr/bin/env python3
"""Generate a quantized MNIST memory image for the standalone FPGA demo.

The hardware demo runs one dense layer:

    scores[10] = W[10][784] * image[784] + bias[10]

This script builds a tiny nearest-centroid linear classifier from MNIST:

    W[class]    = mean training image for that class
    bias[class] = -0.5 * ||W[class]||^2

The classifier is simple, but it maps cleanly onto the int8 dense engine.
"""

from __future__ import annotations

import argparse
import gzip
import json
import struct
import urllib.request
from pathlib import Path

import numpy as np


MNIST_URLS = {
    "train_images": "https://storage.googleapis.com/cvdf-datasets/mnist/train-images-idx3-ubyte.gz",
    "train_labels": "https://storage.googleapis.com/cvdf-datasets/mnist/train-labels-idx1-ubyte.gz",
    "test_images": "https://storage.googleapis.com/cvdf-datasets/mnist/t10k-images-idx3-ubyte.gz",
    "test_labels": "https://storage.googleapis.com/cvdf-datasets/mnist/t10k-labels-idx1-ubyte.gz",
}


INPUT_WORDS = 196
OUTPUTS = 10
MEM_WORDS = 4096

INPUT_WORD_BASE = 0
WEIGHT_WORD_BASE = 256
BIAS_WORD_BASE = WEIGHT_WORD_BASE + OUTPUTS * INPUT_WORDS
OUTPUT_WORD_BASE = BIAS_WORD_BASE + OUTPUTS


def download(url: str, path: Path) -> None:
    if path.exists():
        return

    path.parent.mkdir(parents=True, exist_ok=True)
    print(f"Downloading {url}")
    with urllib.request.urlopen(url, timeout=60) as response:
        path.write_bytes(response.read())


def read_idx_images(path: Path) -> np.ndarray:
    with gzip.open(path, "rb") as f:
        magic, count, rows, cols = struct.unpack(">IIII", f.read(16))
        if magic != 2051:
            raise ValueError(f"{path}: bad image magic {magic}")
        data = np.frombuffer(f.read(), dtype=np.uint8)
    return data.reshape(count, rows * cols)


def read_idx_labels(path: Path) -> np.ndarray:
    with gzip.open(path, "rb") as f:
        magic, count = struct.unpack(">II", f.read(8))
        if magic != 2049:
            raise ValueError(f"{path}: bad label magic {magic}")
        data = np.frombuffer(f.read(), dtype=np.uint8)
    return data.reshape(count)


def quantize_images(images: np.ndarray) -> np.ndarray:
    # Hardware uses signed int8. MNIST pixels are non-negative, so 0..127 works.
    return np.rint(images.astype(np.float32) * (127.0 / 255.0)).astype(np.int8)


def pack_i8x4(values: np.ndarray) -> int:
    word = 0
    for i, value in enumerate(values.tolist()):
        word |= (int(value) & 0xFF) << (8 * i)
    return word


def signed32_to_hex(value: int) -> str:
    return f"{value & 0xFFFF_FFFF:08X}"


def build_centroid_model(train_x_q: np.ndarray, train_y: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    weights = np.zeros((OUTPUTS, 784), dtype=np.int8)
    biases = np.zeros((OUTPUTS,), dtype=np.int32)

    for cls in range(OUTPUTS):
        class_images = train_x_q[train_y == cls].astype(np.int32)
        centroid = np.rint(class_images.mean(axis=0)).astype(np.int32)
        centroid = np.clip(centroid, -128, 127).astype(np.int8)
        weights[cls] = centroid
        biases[cls] = -int(np.sum(centroid.astype(np.int32) * centroid.astype(np.int32)) // 2)

    return weights, biases


def scores_for(images_q: np.ndarray, weights: np.ndarray, biases: np.ndarray) -> np.ndarray:
    return images_q.astype(np.int32) @ weights.astype(np.int32).T + biases.astype(np.int32)


def choose_sample(test_x_q: np.ndarray, test_y: np.ndarray, weights: np.ndarray, biases: np.ndarray) -> int:
    scores = scores_for(test_x_q, weights, biases)
    pred = np.argmax(scores, axis=1)

    # Keep the FPGA top simple: choose a correctly classified zero if possible.
    zero_hits = np.nonzero((test_y == 0) & (pred == 0))[0]
    if len(zero_hits) > 0:
        return int(zero_hits[0])

    hits = np.nonzero(pred == test_y)[0]
    if len(hits) == 0:
        raise RuntimeError("centroid model did not classify any test sample correctly")
    return int(hits[0])


def write_memory_image(
    out_hex: Path,
    out_meta: Path,
    image_q: np.ndarray,
    label: int,
    weights: np.ndarray,
    biases: np.ndarray,
) -> None:
    mem = [0 for _ in range(MEM_WORDS)]

    for word_index in range(INPUT_WORDS):
        lo = word_index * 4
        mem[INPUT_WORD_BASE + word_index] = pack_i8x4(image_q[lo : lo + 4])

    for cls in range(OUTPUTS):
        for word_index in range(INPUT_WORDS):
            lo = word_index * 4
            mem[WEIGHT_WORD_BASE + cls * INPUT_WORDS + word_index] = pack_i8x4(
                weights[cls, lo : lo + 4]
            )

    for cls in range(OUTPUTS):
        mem[BIAS_WORD_BASE + cls] = int(biases[cls]) & 0xFFFF_FFFF

    score = scores_for(image_q.reshape(1, 784), weights, biases)[0]
    pred = int(np.argmax(score))

    out_hex.parent.mkdir(parents=True, exist_ok=True)
    out_hex.write_text("\n".join(f"{word:08X}" for word in mem) + "\n")

    metadata = {
        "input_words": INPUT_WORDS,
        "outputs": OUTPUTS,
        "mem_words": MEM_WORDS,
        "input_word_base": INPUT_WORD_BASE,
        "weight_word_base": WEIGHT_WORD_BASE,
        "bias_word_base": BIAS_WORD_BASE,
        "output_word_base": OUTPUT_WORD_BASE,
        "selected_label": int(label),
        "selected_prediction": pred,
        "scores": [int(x) for x in score.tolist()],
    }
    out_meta.write_text(json.dumps(metadata, indent=2) + "\n")

    print(f"Wrote {out_hex}")
    print(f"Wrote {out_meta}")
    print(f"Selected MNIST label={label} prediction={pred}")
    print(f"Scores={metadata['scores']}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--data-dir", default="data/mnist")
    parser.add_argument(
        "--out-hex",
        default="build/mnist_demo/mnist_demo_mem.hex",
    )
    parser.add_argument(
        "--out-meta",
        default="build/mnist_demo/mnist_demo_metadata.json",
    )
    args = parser.parse_args()

    data_dir = Path(args.data_dir)
    paths = {name: data_dir / Path(url).name for name, url in MNIST_URLS.items()}

    for name, url in MNIST_URLS.items():
        download(url, paths[name])

    train_x = read_idx_images(paths["train_images"])
    train_y = read_idx_labels(paths["train_labels"])
    test_x = read_idx_images(paths["test_images"])
    test_y = read_idx_labels(paths["test_labels"])

    train_x_q = quantize_images(train_x)
    test_x_q = quantize_images(test_x)

    weights, biases = build_centroid_model(train_x_q, train_y)
    sample_index = choose_sample(test_x_q, test_y, weights, biases)

    write_memory_image(
        Path(args.out_hex),
        Path(args.out_meta),
        test_x_q[sample_index],
        int(test_y[sample_index]),
        weights,
        biases,
    )


if __name__ == "__main__":
    main()
