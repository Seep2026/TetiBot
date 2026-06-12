#!/usr/bin/env python3
"""Build Teti Track 128x128 preview sheets with only the Python stdlib.

The Aseprite CLI exports individual RGBA PNG frames. This script composes those
frames into transparent preview grids, the runtime master sheet, and the markdown
manifest. It intentionally avoids Pillow so a fresh macOS environment can run it
with the system Python alone.
"""

from __future__ import annotations

import argparse
import math
import os
import struct
import sys
import zlib
from dataclasses import dataclass
from pathlib import Path


PNG_SIG = b"\x89PNG\r\n\x1a\n"
CELL = 128


@dataclass(frozen=True)
class Asset:
    name: str
    rel: str


SHEET_ASSETS = [
    Asset("teti_track_front_neutral_128", "body/teti_track_front_neutral_128.png"),
    Asset("teti_track_side_128", "body/teti_track_side_128.png"),
    Asset("face_neutral_128", "faces/face_neutral_128.png"),
    Asset("face_blink_128", "faces/face_blink_128.png"),
    Asset("face_sleepy_128", "faces/face_sleepy_128.png"),
    Asset("face_focused_128", "faces/face_focused_128.png"),
    Asset("face_warning_128", "faces/face_warning_128.png"),
    Asset("face_collapsed_128", "faces/face_collapsed_128.png"),
    Asset("idle_1_128", "motion/idle_1_128.png"),
    Asset("idle_2_128", "motion/idle_2_128.png"),
    Asset("move_left_1_128", "motion/move_left_1_128.png"),
    Asset("move_right_1_128", "motion/move_right_1_128.png"),
    Asset("hat_none_128", "hats/hat_none_128.png"),
    Asset("hat_beanie_128", "hats/hat_beanie_128.png"),
    Asset("hat_engineer_128", "hats/hat_engineer_128.png"),
    Asset("hat_antenna_128", "hats/hat_antenna_128.png"),
    Asset("hat_warning_light_128", "hats/hat_warning_light_128.png"),
    Asset("hat_sprout_128", "hats/hat_sprout_128.png"),
]

FACE_PREVIEW = [
    "faces/face_neutral_128.png",
    "faces/face_blink_128.png",
    "faces/face_sleepy_128.png",
    "faces/face_focused_128.png",
    "faces/face_warning_128.png",
    "faces/face_collapsed_128.png",
]

MOTION_FRAMES = [
    "motion/idle_1_128.png",
    "motion/idle_2_128.png",
    "motion/move_left_1_128.png",
    "motion/move_right_1_128.png",
]

MOTION_PREVIEW = [
    "motion/idle_1_128.png",
    "motion/move_left_1_128.png",
    "motion/move_right_1_128.png",
]

HAT_PREVIEW = [
    "hats/hat_none_128.png",
    "hats/hat_beanie_128.png",
    "hats/hat_engineer_128.png",
    "hats/hat_antenna_128.png",
    "hats/hat_warning_light_128.png",
    "hats/hat_sprout_128.png",
]

FONT = {
    "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
    "C": ["01111", "10000", "10000", "10000", "10000", "10000", "01111"],
    "D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
    "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
    "F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
    "H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
    "I": ["11111", "00100", "00100", "00100", "00100", "00100", "11111"],
    "M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
    "N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
    "O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
    "P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
    "R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
    "S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
    "T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
    "V": ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
}


class Image:
    def __init__(self, width: int, height: int, pixels: bytearray | None = None):
        self.width = width
        self.height = height
        self.pixels = pixels or bytearray(width * height * 4)

    @classmethod
    def solid(cls, width: int, height: int, rgba: tuple[int, int, int, int]) -> "Image":
        image = cls(width, height)
        for y in range(height):
            for x in range(width):
                image.set_pixel(x, y, rgba)
        return image

    def set_pixel(self, x: int, y: int, rgba: tuple[int, int, int, int]) -> None:
        if x < 0 or y < 0 or x >= self.width or y >= self.height:
            return
        i = (y * self.width + x) * 4
        self.pixels[i : i + 4] = bytes(rgba)

    def get_pixel(self, x: int, y: int) -> tuple[int, int, int, int]:
        i = (y * self.width + x) * 4
        return tuple(self.pixels[i : i + 4])  # type: ignore[return-value]


def read_chunks(data: bytes):
    if not data.startswith(PNG_SIG):
        raise ValueError("not a PNG file")
    offset = len(PNG_SIG)
    while offset < len(data):
        length = struct.unpack(">I", data[offset : offset + 4])[0]
        chunk_type = data[offset + 4 : offset + 8]
        chunk_data = data[offset + 8 : offset + 8 + length]
        yield chunk_type, chunk_data
        offset += 12 + length


def paeth(a: int, b: int, c: int) -> int:
    p = a + b - c
    pa = abs(p - a)
    pb = abs(p - b)
    pc = abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    if pb <= pc:
        return b
    return c


def read_png(path: Path) -> Image:
    width = height = color_type = bit_depth = None
    idat = bytearray()
    for chunk_type, chunk_data in read_chunks(path.read_bytes()):
        if chunk_type == b"IHDR":
            width, height, bit_depth, color_type, compression, filter_method, interlace = struct.unpack(
                ">IIBBBBB", chunk_data
            )
            if compression != 0 or filter_method != 0 or interlace != 0:
                raise ValueError(f"unsupported PNG format: {path}")
        elif chunk_type == b"IDAT":
            idat.extend(chunk_data)

    if width is None or height is None or color_type is None or bit_depth != 8:
        raise ValueError(f"unsupported PNG header: {path}")

    if color_type == 6:
        channels = 4
    elif color_type == 2:
        channels = 3
    else:
        raise ValueError(f"unsupported PNG color type {color_type}: {path}")

    raw = zlib.decompress(bytes(idat))
    stride = width * channels
    recon = bytearray()
    previous = bytearray(stride)
    pos = 0

    for _ in range(height):
        filter_type = raw[pos]
        pos += 1
        scanline = bytearray(raw[pos : pos + stride])
        pos += stride
        for i in range(stride):
            left = scanline[i - channels] if i >= channels else 0
            up = previous[i]
            upper_left = previous[i - channels] if i >= channels else 0
            if filter_type == 1:
                scanline[i] = (scanline[i] + left) & 0xFF
            elif filter_type == 2:
                scanline[i] = (scanline[i] + up) & 0xFF
            elif filter_type == 3:
                scanline[i] = (scanline[i] + ((left + up) // 2)) & 0xFF
            elif filter_type == 4:
                scanline[i] = (scanline[i] + paeth(left, up, upper_left)) & 0xFF
            elif filter_type != 0:
                raise ValueError(f"unsupported PNG filter {filter_type}: {path}")
        recon.extend(scanline)
        previous = scanline

    pixels = bytearray(width * height * 4)
    if channels == 4:
        pixels[:] = recon
    else:
        j = 0
        for i in range(0, len(recon), 3):
            pixels[j : j + 4] = bytes((recon[i], recon[i + 1], recon[i + 2], 255))
            j += 4
    return Image(width, height, pixels)


def chunk(chunk_type: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + chunk_type + data + struct.pack(">I", zlib.crc32(chunk_type + data) & 0xFFFFFFFF)


def write_png(path: Path, image: Image) -> None:
    raw = bytearray()
    stride = image.width * 4
    for y in range(image.height):
        raw.append(0)
        start = y * stride
        raw.extend(image.pixels[start : start + stride])
    data = bytearray(PNG_SIG)
    data.extend(chunk(b"IHDR", struct.pack(">IIBBBBB", image.width, image.height, 8, 6, 0, 0, 0)))
    data.extend(chunk(b"IDAT", zlib.compress(bytes(raw), 9)))
    data.extend(chunk(b"IEND", b""))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(bytes(data))


def alpha_paste(dst: Image, src: Image, x0: int, y0: int) -> None:
    for y in range(src.height):
        dy = y0 + y
        if dy < 0 or dy >= dst.height:
            continue
        for x in range(src.width):
            dx = x0 + x
            if dx < 0 or dx >= dst.width:
                continue
            si = (y * src.width + x) * 4
            sr, sg, sb, sa = src.pixels[si : si + 4]
            if sa == 0:
                continue
            di = (dy * dst.width + dx) * 4
            dr, dg, db, da = dst.pixels[di : di + 4]
            src_a = sa / 255.0
            dst_a = da / 255.0
            out_a_float = src_a + dst_a * (1.0 - src_a)
            out_a = int(round(out_a_float * 255))
            if out_a == 0:
                dst.pixels[di : di + 4] = b"\x00\x00\x00\x00"
                continue
            dst.pixels[di] = int(round((sr * src_a + dr * dst_a * (1.0 - src_a)) / out_a_float))
            dst.pixels[di + 1] = int(round((sg * src_a + dg * dst_a * (1.0 - src_a)) / out_a_float))
            dst.pixels[di + 2] = int(round((sb * src_a + db * dst_a * (1.0 - src_a)) / out_a_float))
            dst.pixels[di + 3] = int(out_a)


def fill_rect(image: Image, x: int, y: int, w: int, h: int, rgba: tuple[int, int, int, int]) -> None:
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            image.set_pixel(xx, yy, rgba)


def stroke_rect(image: Image, x: int, y: int, w: int, h: int, rgba: tuple[int, int, int, int]) -> None:
    fill_rect(image, x, y, w, 1, rgba)
    fill_rect(image, x, y + h - 1, w, 1, rgba)
    fill_rect(image, x, y, 1, h, rgba)
    fill_rect(image, x + w - 1, y, 1, h, rgba)


def checker(image: Image, x: int, y: int, w: int, h: int, tile: int = 8) -> None:
    c1 = (238, 247, 244, 255)
    c2 = (220, 234, 230, 255)
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            image.set_pixel(xx, yy, c1 if ((xx - x) // tile + (yy - y) // tile) % 2 == 0 else c2)


def draw_text(image: Image, text: str, x: int, y: int, scale: int = 3, rgba: tuple[int, int, int, int] = (33, 43, 49, 255)) -> None:
    cursor = x
    for char in text.upper():
        if char == " ":
            cursor += 4 * scale
            continue
        glyph = FONT.get(char)
        if not glyph:
            cursor += 6 * scale
            continue
        for gy, row in enumerate(glyph):
            for gx, bit in enumerate(row):
                if bit == "1":
                    fill_rect(image, cursor + gx * scale, y + gy * scale, scale, scale, rgba)
        cursor += 6 * scale


def load_asset(asset_root: Path, rel: str) -> Image:
    path = asset_root / rel
    if not path.exists():
        raise FileNotFoundError(path)
    image = read_png(path)
    if image.width != CELL or image.height != CELL:
        raise ValueError(f"expected {CELL}x{CELL}: {path}")
    return image


def make_grid(asset_root: Path, rels: list[str], columns: int) -> Image:
    rows = math.ceil(len(rels) / columns)
    out = Image(columns * CELL, rows * CELL)
    for idx, rel in enumerate(rels):
        alpha_paste(out, load_asset(asset_root, rel), (idx % columns) * CELL, (idx // columns) * CELL)
    return out


def build_sheet(asset_root: Path) -> None:
    columns = 6
    out = Image(columns * CELL, 3 * CELL)
    for idx, asset in enumerate(SHEET_ASSETS):
        alpha_paste(out, load_asset(asset_root, asset.rel), (idx % columns) * CELL, (idx // columns) * CELL)
    write_png(asset_root / "sheets/teti_track_master_sheet_128.png", out)

    lines = [
        "# Teti Track Master Sheet 128",
        "",
        "- cell size: 128x128",
        "- columns: 6",
        "- rows: 3",
        "- image: `teti_track_master_sheet_128.png`",
        "",
        "| name | x | y | w | h |",
        "|---|---:|---:|---:|---:|",
    ]
    for idx, asset in enumerate(SHEET_ASSETS):
        x = (idx % columns) * CELL
        y = (idx // columns) * CELL
        lines.append(f"| `{asset.name}` | {x} | {y} | {CELL} | {CELL} |")
    lines.append("")
    (asset_root / "sheets/teti_track_master_sheet_128.md").write_text("\n".join(lines), encoding="utf-8")


def panel(image: Image, x: int, y: int, w: int, h: int, title: str) -> None:
    fill_rect(image, x, y, w, h, (255, 255, 255, 255))
    stroke_rect(image, x, y, w, h, (181, 204, 200, 255))
    draw_text(image, title, x + 14, y + 14)


def preview_sprite(image: Image, sprite: Image, x: int, y: int) -> None:
    checker(image, x, y, CELL, CELL)
    alpha_paste(image, sprite, x, y)


def build_master_preview(asset_root: Path) -> None:
    out = Image.solid(1024, 1024, (235, 242, 242, 255))
    front = load_asset(asset_root, "body/teti_track_front_neutral_128.png")
    side = load_asset(asset_root, "body/teti_track_side_128.png")
    motion = [load_asset(asset_root, rel) for rel in MOTION_PREVIEW]
    hats = [load_asset(asset_root, rel) for rel in HAT_PREVIEW]
    faces = [load_asset(asset_root, rel) for rel in FACE_PREVIEW]

    panel(out, 24, 24, 224, 224, "FRONT")
    preview_sprite(out, front, 72, 72)

    panel(out, 272, 24, 224, 224, "SIDE")
    preview_sprite(out, side, 320, 72)

    panel(out, 520, 24, 480, 224, "MOVE")
    for i, sprite in enumerate(motion):
        preview_sprite(out, sprite, 568 + i * 144, 72)

    panel(out, 24, 272, 480, 360, "HATS")
    for i, sprite in enumerate(hats):
        preview_sprite(out, sprite, 72 + (i % 3) * 144, 320 + (i // 3) * 144)

    panel(out, 520, 272, 480, 360, "FACES")
    for i, sprite in enumerate(faces):
        preview_sprite(out, sprite, 568 + (i % 3) * 144, 320 + (i // 3) * 144)

    panel(out, 24, 656, 976, 320, "PARTS")
    preview_sprite(out, front, 328, 724)
    preview_sprite(out, faces[0], 456, 724)
    preview_sprite(out, hats[3], 584, 724)

    write_png(asset_root / "previews/teti_track_master_preview_128.png", out)


def build_previews(asset_root: Path, rebuild_master_preview: bool) -> None:
    write_png(asset_root / "previews/teti_track_faces_preview_128.png", make_grid(asset_root, FACE_PREVIEW, 3))
    write_png(asset_root / "previews/teti_track_motion_preview_128.png", make_grid(asset_root, MOTION_PREVIEW, 3))
    write_png(asset_root / "previews/teti_track_hats_preview_128.png", make_grid(asset_root, HAT_PREVIEW, 3))
    master_preview = asset_root / "previews/teti_track_master_preview_128.png"
    if rebuild_master_preview or not master_preview.exists():
        build_master_preview(asset_root)
    else:
        print(f"preserved curated master preview: {master_preview}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--asset-root", required=True, type=Path)
    parser.add_argument(
        "--rebuild-master-preview",
        action="store_true",
        help="replace teti_track_master_preview_128.png with the generated fallback overview",
    )
    args = parser.parse_args()

    asset_root = args.asset_root.resolve()
    build_previews(asset_root, args.rebuild_master_preview)
    build_sheet(asset_root)
    print(f"wrote previews and sheets under {asset_root}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
