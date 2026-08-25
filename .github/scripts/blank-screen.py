#!/usr/bin/env python3
"""Decide whether a screenshot is a blank screen.

The launch smoke test needs to tell "the app is up" from "the app is up and
drawing something", because those are not the same failure and only one of them
shows up as a dead process. An app that renders nothing stays alive forever.

Reads a small BMP (sips converts the screenshot; BMP so this needs no image
library on the runner) and reports the share of the frame taken by its single
most common colour. A real screen — even a mostly-cream one — has a title, a
tab bar and a tile grid in it, so it never lands near 100% one colour. A blank
one does.

Prints: "<yes|no> dominant=<hex> share=<f> distinct=<n>", and exits 0 either
way — the caller decides what to do with the verdict.
"""

import collections
import struct
import sys


def dominant_share(path: str) -> tuple[str, float, int]:
    raw = open(path, "rb").read()

    pixel_offset = struct.unpack_from("<I", raw, 10)[0]
    width, height = struct.unpack_from("<ii", raw, 18)
    bits_per_pixel = struct.unpack_from("<H", raw, 28)[0]

    stride = bits_per_pixel // 8
    # BMP rows are padded to a four-byte boundary.
    row_bytes = ((width * stride + 3) // 4) * 4

    counts: collections.Counter = collections.Counter()
    for y in range(abs(height)):
        row_start = pixel_offset + y * row_bytes
        for x in range(width):
            i = row_start + x * stride
            counts[raw[i:i + 3]] += 1

    total = sum(counts.values())
    colour, n = counts.most_common(1)[0]
    return colour.hex(), n / total, len(counts)


def main() -> int:
    try:
        colour, share, distinct = dominant_share(sys.argv[1])
    except Exception as error:  # noqa: BLE001 - a broken read must not fail the job
        print(f"unknown {error}")
        return 0

    # 0.97 rather than 1.0: the simulator's status bar and home indicator are
    # always drawn by the system, so even a completely blank app is not quite
    # a single colour.
    verdict = "yes" if share > 0.97 else "no"
    print(f"{verdict} dominant={colour} share={share:.3f} distinct={distinct}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
