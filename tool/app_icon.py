#!/usr/bin/env python3
"""Derive the macOS app-icon set from the platform-neutral source artwork.

The SOURCE is `docs/brand/app-icon-source.png`: the artwork as drawn, a full
1024×1024 square, never cropped or masked — Windows and Linux will want the
whole square (their icons carry no rounded mask), so it is kept intact and
every platform derives from it.

macOS is the one platform that does NOT mask app icons: the icon itself must
be Apple's rounded square with transparent margins (an 824×824 body, corner
radius 186, centred on a 1024 canvas) or it sits oversized and square beside
every other Dock icon. This script does that derivation — sRGB conversion,
scale to the body, antialiased rounded-corner mask, then the seven sizes the
asset catalogue lists — with nothing but `sips` and the standard library, so
it runs on any Mac.

    tool/app_icon.py            # regenerate macos/Runner/Assets.xcassets/AppIcon.appiconset/*.png
"""

from __future__ import annotations

import struct
import subprocess
import sys
import tempfile
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "docs/brand/app-icon-source.png"
APPICONSET = ROOT / "macos/Runner/Assets.xcassets/AppIcon.appiconset"
SIZES = (16, 32, 64, 128, 256, 512, 1024)

CANVAS = 1024
BODY = 824  # Apple's icon grid: ~10% margin each side
RADIUS = 186.0
SRGB = "/System/Library/ColorSync/Profiles/sRGB Profile.icc"


def sips(*args: str) -> None:
    subprocess.run(["sips", *args], check=True, capture_output=True)


def read_png(path: Path) -> tuple[int, int, int, list[bytearray]]:
    data = path.read_bytes()
    pos, idat, w, h, ct = 8, b"", 0, 0, 0
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos : pos + 4])
        kind = data[pos + 4 : pos + 8]
        body = data[pos + 8 : pos + 8 + length]
        pos += 12 + length
        if kind == b"IHDR":
            w, h, depth, ct = struct.unpack(">IIBB", body[:10])
            if depth != 8 or ct not in (2, 6):
                sys.exit(f"{path}: need 8-bit RGB or RGBA, got depth {depth} type {ct}")
        elif kind == b"IDAT":
            idat += body
    raw = zlib.decompress(idat)
    channels = 4 if ct == 6 else 3
    stride = w * channels
    rows: list[bytearray] = []
    prev = bytearray(stride)
    p = 0

    def paeth(a: int, b: int, c: int) -> int:
        pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
        return a if pa <= pb and pa <= pc else (b if pb <= pc else c)

    for _ in range(h):
        filt = raw[p]
        p += 1
        line = bytearray(raw[p : p + stride])
        p += stride
        for i in range(stride):
            a = line[i - channels] if i >= channels else 0
            b = prev[i]
            c = prev[i - channels] if i >= channels else 0
            if filt == 1:
                line[i] = (line[i] + a) & 255
            elif filt == 2:
                line[i] = (line[i] + b) & 255
            elif filt == 3:
                line[i] = (line[i] + (a + b) // 2) & 255
            elif filt == 4:
                line[i] = (line[i] + paeth(a, b, c)) & 255
        rows.append(line)
        prev = line
    return w, h, channels, rows


def write_png(path: Path, w: int, h: int, rows: list[bytearray]) -> None:
    def chunk(kind: bytes, body: bytes) -> bytes:
        crc = zlib.crc32(kind + body) & 0xFFFFFFFF
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", crc)

    raw = b"".join(b"\x00" + bytes(r) for r in rows)
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


def coverage(x: int, y: int) -> float:
    """Fraction of pixel (x, y) inside the rounded square — 4×4 supersampled."""
    inside = 0
    for sy in range(4):
        for sx in range(4):
            px, py = x + (sx + 0.5) / 4, y + (sy + 0.5) / 4
            cx = min(max(px, RADIUS), BODY - RADIUS)
            cy = min(max(py, RADIUS), BODY - RADIUS)
            if (px - cx) ** 2 + (py - cy) ** 2 <= RADIUS * RADIUS:
                inside += 1
    return inside / 16


def main() -> None:
    if not SOURCE.exists():
        sys.exit(f"source artwork missing: {SOURCE}")
    with tempfile.TemporaryDirectory() as tmp:
        srgb = Path(tmp, "srgb.png")
        body = Path(tmp, "body.png")
        sips("-s", "format", "png", "--matchTo", SRGB, str(SOURCE), "--out", str(srgb))
        sips("-z", str(BODY), str(BODY), str(srgb), "--out", str(body))
        w, h, channels, rows = read_png(body)
        if (w, h) != (BODY, BODY):
            sys.exit(f"expected {BODY}x{BODY} body, got {w}x{h}")

        off = (CANVAS - BODY) // 2
        out = [bytearray(CANVAS * 4) for _ in range(CANVAS)]
        for y in range(BODY):
            src, dst = rows[y], out[y + off]
            for x in range(BODY):
                near_corner = (x < RADIUS or x > BODY - RADIUS) and (
                    y < RADIUS or y > BODY - RADIUS
                )
                a = coverage(x, y) if near_corner else 1.0
                if a == 0:
                    continue
                o = x * channels
                src_alpha = src[o + 3] if channels == 4 else 255
                d = (x + off) * 4
                dst[d], dst[d + 1], dst[d + 2] = src[o], src[o + 1], src[o + 2]
                dst[d + 3] = round(src_alpha * a)

        master = APPICONSET / "app_icon_1024.png"
        write_png(master, CANVAS, CANVAS, out)
        for n in SIZES[:-1]:
            sips("-z", str(n), str(n), str(master), "--out", str(APPICONSET / f"app_icon_{n}.png"))
    print(f"wrote {len(SIZES)} sizes to {APPICONSET.relative_to(ROOT)} from {SOURCE.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
