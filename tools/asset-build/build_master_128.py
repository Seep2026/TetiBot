#!/usr/bin/env python3
"""Build Teti Track 128x128 preview sheets with only the Python stdlib.

The Aseprite CLI exports individual RGBA PNG frames. This script composes those
frames into transparent preview grids, the runtime master sheet, and the markdown
manifest. It intentionally avoids Pillow so a fresh macOS environment can run it
with the system Python alone.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import struct
import sys
import zlib
from dataclasses import dataclass
from pathlib import Path


PNG_SIG = b"\x89PNG\r\n\x1a\n"
CELL = 128
HAT_SOURCE_PATH = "art/aseprite/hats/teti_track_hat_master.aseprite"
HAT_RUNTIME_ROOT = "pet-runtime/assets/master_128/hats"


@dataclass(frozen=True)
class Asset:
    name: str
    rel: str


CORE_SHEET_ASSETS = [
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
]

TRACK_MOTION_ASSETS = [
    Asset("idle_breathe_01_128", "motion/track/idle_breathe_01_128.png"),
    Asset("idle_breathe_02_128", "motion/track/idle_breathe_02_128.png"),
    Asset("idle_breathe_03_128", "motion/track/idle_breathe_03_128.png"),
    Asset("idle_breathe_04_128", "motion/track/idle_breathe_04_128.png"),
    Asset("move_left_01_128", "motion/track/move_left_01_128.png"),
    Asset("move_left_02_128", "motion/track/move_left_02_128.png"),
    Asset("move_left_03_128", "motion/track/move_left_03_128.png"),
    Asset("move_left_04_128", "motion/track/move_left_04_128.png"),
    Asset("move_left_05_128", "motion/track/move_left_05_128.png"),
    Asset("move_left_06_128", "motion/track/move_left_06_128.png"),
    Asset("move_right_01_128", "motion/track/move_right_01_128.png"),
    Asset("move_right_02_128", "motion/track/move_right_02_128.png"),
    Asset("move_right_03_128", "motion/track/move_right_03_128.png"),
    Asset("move_right_04_128", "motion/track/move_right_04_128.png"),
    Asset("move_right_05_128", "motion/track/move_right_05_128.png"),
    Asset("move_right_06_128", "motion/track/move_right_06_128.png"),
]

FACE_OVERLAY_ASSETS = [
    Asset("face_clear_128", "faces/overlays/face_clear_128.png"),
    Asset("face_overlay_neutral_128", "faces/overlays/face_overlay_neutral_128.png"),
    Asset("face_overlay_blink_128", "faces/overlays/face_overlay_blink_128.png"),
    Asset("face_overlay_sleepy_128", "faces/overlays/face_overlay_sleepy_128.png"),
    Asset("face_overlay_focused_128", "faces/overlays/face_overlay_focused_128.png"),
    Asset("face_overlay_warning_128", "faces/overlays/face_overlay_warning_128.png"),
    Asset("face_overlay_collapsed_128", "faces/overlays/face_overlay_collapsed_128.png"),
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
    *(asset.rel for asset in TRACK_MOTION_ASSETS),
]

MASTER_MOTION_PREVIEW = [
    "motion/track/idle_breathe_01_128.png",
    "motion/track/move_left_01_128.png",
    "motion/track/move_right_01_128.png",
]

FACE_OVERLAY_BOUNDS = (34, 31, 94, 72)

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


def load_hat_manifest(path: Path) -> dict:
    payload = json.loads(path.read_text(encoding="utf-8"))
    hats = payload.get("hats")
    if not isinstance(hats, list) or not hats:
        raise ValueError(f"hat manifest has no hats: {path}")

    if len(hats) != 18:
        raise ValueError(f"hat manifest must contain exactly 18 hats: {path}")

    seen: set[str] = set()
    seen_files: set[str] = set()
    seen_frames: set[int] = set()
    for index, hat in enumerate(hats):
        hat_id = hat.get("id")
        filename = hat.get("file")
        if not hat_id or not filename:
            raise ValueError(f"hat entries require id and file: {path}")
        if hat_id in seen:
            raise ValueError(f"duplicate hat id {hat_id}: {path}")
        if filename in seen_files:
            raise ValueError(f"duplicate hat file {filename}: {path}")
        if filename != f"hat_{hat_id}_128.png":
            raise ValueError(f"hat file must match its id: {hat_id} -> {filename}")
        if hat.get("source_frame") != index:
            raise ValueError(f"hat {hat_id} must map source frame {index}: {path}")
        if index in seen_frames:
            raise ValueError(f"duplicate source frame {index}: {path}")
        if any(part in filename.lower() for part in ("debug", "deprecated", "fallback", "codex")):
            raise ValueError(f"forbidden production hat path: {filename}")
        seen.add(hat_id)
        seen_files.add(filename)
        seen_frames.add(index)
    return payload


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def hat_assets(hat_manifest: dict) -> list[Asset]:
    return [Asset(f"hat_{hat['id']}_128", f"hats/{hat['file']}") for hat in hat_manifest["hats"]]


def alpha_pixel_count(image: Image) -> int:
    return sum(1 for i in range(3, len(image.pixels), 4) if image.pixels[i] > 0)


def nontransparent_bounds(image: Image) -> tuple[int, int, int, int] | None:
    points = [
        (x, y)
        for y in range(image.height)
        for x in range(image.width)
        if image.get_pixel(x, y)[3] > 0
    ]
    if not points:
        return None
    return (
        min(x for x, _ in points),
        min(y for _, y in points),
        max(x for x, _ in points),
        max(y for _, y in points),
    )


def build_hat_outputs(asset_root: Path, hat_manifest: dict) -> None:
    hats_dir = asset_root / "hats"
    hats_dir.mkdir(parents=True, exist_ok=True)
    definitions = hat_manifest["hats"]

    bounds = hat_manifest["bounds"]
    min_x = bounds["x"]
    min_y = bounds["y"]
    max_x = min_x + bounds["w"] - 1
    max_y = min_y + bounds["h"] - 1
    for hat in definitions:
        path = hats_dir / hat["file"]
        image = load_asset(asset_root, f"hats/{hat['file']}")
        opaque_bounds = nontransparent_bounds(image)
        if opaque_bounds is None:
            if hat["id"] != "none":
                raise ValueError(f"hat has no visible pixels: {path}")
            continue
        x0, y0, x1, y1 = opaque_bounds
        if x0 < min_x or y0 < min_y or x1 > max_x or y1 > max_y:
            raise ValueError(
                f"hat exceeds head bounds {min_x},{min_y}-{max_x},{max_y}: {path} has {opaque_bounds}"
            )

    (hats_dir / "hats_manifest.json").write_text(
        json.dumps(hat_manifest, indent=2) + "\n",
        encoding="utf-8",
    )


def make_grid(asset_root: Path, rels: list[str], columns: int) -> Image:
    rows = math.ceil(len(rels) / columns)
    out = Image(columns * CELL, rows * CELL)
    for idx, rel in enumerate(rels):
        alpha_paste(out, load_asset(asset_root, rel), (idx % columns) * CELL, (idx // columns) * CELL)
    return out


def make_hat_grid(asset_root: Path, rels: list[str], columns: int) -> Image:
    rows = math.ceil(len(rels) / columns)
    out = Image(columns * CELL, rows * CELL)
    body = load_asset(asset_root, "body/teti_track_front_neutral_128.png")
    for idx, rel in enumerate(rels):
        composite = Image(CELL, CELL, bytearray(body.pixels))
        alpha_paste(composite, load_asset(asset_root, rel), 0, 0)
        alpha_paste(out, composite, (idx % columns) * CELL, (idx // columns) * CELL)
    return out


def nearest_resize(source: Image, width: int, height: int) -> Image:
    out = Image(width, height)
    for y in range(height):
        source_y = min(source.height - 1, y * source.height // height)
        for x in range(width):
            source_x = min(source.width - 1, x * source.width // width)
            out.set_pixel(x, y, source.get_pixel(source_x, source_y))
    return out


def make_hat_grid_64(asset_root: Path, rels: list[str], columns: int) -> Image:
    rows = math.ceil(len(rels) / columns)
    out = Image(columns * 64, rows * 64)
    body = load_asset(asset_root, "body/teti_track_front_neutral_128.png")
    for idx, rel in enumerate(rels):
        composite = Image(CELL, CELL, bytearray(body.pixels))
        alpha_paste(composite, load_asset(asset_root, rel), 0, 0)
        alpha_paste(out, nearest_resize(composite, 64, 64), (idx % columns) * 64, (idx // columns) * 64)
    return out


def is_face_pixel(px: tuple[int, int, int, int]) -> bool:
    r, g, b, a = px
    if a == 0:
        return False
    is_dark = r <= 45 and g <= 50 and b <= 70
    is_highlight = r >= 240 and g >= 240 and b >= 220
    return is_dark or is_highlight


def make_face_clear_patch(neutral: Image) -> Image:
    x0, y0, x1, y1 = FACE_OVERLAY_BOUNDS
    out = Image(CELL, CELL)
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            px = neutral.get_pixel(x, y)
            if px[3] > 0 and not is_face_pixel(px):
                out.set_pixel(x, y, px)
    return out


def make_face_overlay(face: Image) -> Image:
    x0, y0, x1, y1 = FACE_OVERLAY_BOUNDS
    out = Image(CELL, CELL)
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            px = face.get_pixel(x, y)
            if is_face_pixel(px):
                out.set_pixel(x, y, px)
    return out


def build_face_overlay_outputs(asset_root: Path) -> None:
    faces = [
        ("neutral", "faces/face_neutral_128.png"),
        ("blink", "faces/face_blink_128.png"),
        ("sleepy", "faces/face_sleepy_128.png"),
        ("focused", "faces/face_focused_128.png"),
        ("warning", "faces/face_warning_128.png"),
        ("collapsed", "faces/face_collapsed_128.png"),
    ]
    neutral = load_asset(asset_root, "faces/face_neutral_128.png")
    write_png(asset_root / "faces/overlays/face_clear_128.png", make_face_clear_patch(neutral))
    for name, rel in faces:
        write_png(asset_root / f"faces/overlays/face_overlay_{name}_128.png", make_face_overlay(load_asset(asset_root, rel)))


def build_asset_sheet(asset_root: Path, assets: list[Asset], columns: int) -> Image:
    rows = math.ceil(len(assets) / columns)
    out = Image(columns * CELL, rows * CELL)
    for idx, asset in enumerate(assets):
        alpha_paste(out, load_asset(asset_root, asset.rel), (idx % columns) * CELL, (idx // columns) * CELL)
    return out


def write_manifest(path: Path, image_name: str, assets: list[Asset], columns: int) -> None:
    rows = math.ceil(len(assets) / columns)
    payload = {
        "image": image_name,
        "cell": {"w": CELL, "h": CELL},
        "columns": columns,
        "rows": rows,
        "animations": {
            "idle_breathe": {
                "frames": [asset.name for asset in TRACK_MOTION_ASSETS[:4]],
                "fps": 2,
            },
            "move_left": {
                "frames": [asset.name for asset in TRACK_MOTION_ASSETS[4:10]],
                "fps": {"low": 5, "normal": 8, "high": 12},
            },
            "move_right": {
                "frames": [asset.name for asset in TRACK_MOTION_ASSETS[10:16]],
                "fps": {"low": 5, "normal": 8, "high": 12},
            },
        },
        "frames": [],
    }
    for idx, asset in enumerate(assets):
        payload["frames"].append(
            {
                "name": asset.name,
                "x": (idx % columns) * CELL,
                "y": (idx // columns) * CELL,
                "w": CELL,
                "h": CELL,
            }
        )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def build_track_motion_outputs(asset_root: Path) -> None:
    image_name = "teti_track_motion_track_sheet_128.png"
    sheet = build_asset_sheet(asset_root, TRACK_MOTION_ASSETS, 6)
    write_png(asset_root / f"motion/track/{image_name}", sheet)
    write_manifest(asset_root / "motion/track/teti_track_motion_track_sheet_128.json", image_name, TRACK_MOTION_ASSETS, 6)


def lua_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=True)


def write_runtime_manifests(
    asset_root: Path,
    runtime_assets: list[Asset],
    hat_manifest: dict,
    hat_master: Path,
    hat_manifest_path: Path,
    runtime_sheet: Path,
) -> None:
    indices = {asset.name: idx + 1 for idx, asset in enumerate(runtime_assets)}
    runtime_dir = asset_root.parent.parent / "lua"
    body_bounds = nontransparent_bounds(load_asset(asset_root, "body/teti_track_front_neutral_128.png"))
    if body_bounds is None:
        raise ValueError("front body sprite has no visible pixels")
    body_x0, body_y0, body_x1, body_y1 = body_bounds

    def frame(name: str) -> int:
        if name not in indices:
            raise ValueError(f"runtime sprite is missing from sheet: {name}")
        return indices[name]

    sprite_lines = [
        "-- Generated by tools/asset-build/build_master_128.py. Do not edit by hand.",
        "return {",
        f"  front = {frame('teti_track_front_neutral_128')},",
        f"  side = {frame('teti_track_side_128')},",
        f"  face_neutral = {frame('face_neutral_128')},",
        f"  face_blink = {frame('face_blink_128')},",
        f"  idle_1 = {frame('idle_1_128')},",
        f"  idle_2 = {frame('idle_2_128')},",
        f"  move_left = {frame('move_left_1_128')},",
        f"  move_right = {frame('move_right_1_128')},",
        "  body_bounds = { x = %d, y = %d, w = %d, h = %d },"
        % (body_x0, body_y0, body_x1 - body_x0 + 1, body_y1 - body_y0 + 1),
        "  idle_breathe = { " + ", ".join(str(frame(asset.name)) for asset in TRACK_MOTION_ASSETS[:4]) + " },",
        "  move_left_track = { " + ", ".join(str(frame(asset.name)) for asset in TRACK_MOTION_ASSETS[4:10]) + " },",
        "  move_right_track = { " + ", ".join(str(frame(asset.name)) for asset in TRACK_MOTION_ASSETS[10:16]) + " },",
        f"  face_clear = {frame('face_clear_128')},",
        "  face_overlay = {",
        f"    neutral = {frame('face_overlay_neutral_128')},",
        f"    blink = {frame('face_overlay_blink_128')},",
        f"    sleepy = {frame('face_overlay_sleepy_128')},",
        f"    focused = {frame('face_overlay_focused_128')},",
        f"    warning = {frame('face_overlay_warning_128')},",
        f"    collapsed = {frame('face_overlay_collapsed_128')},",
        "  },",
        "}",
        "",
    ]
    (runtime_dir / "sprites_manifest.lua").write_text("\n".join(sprite_lines), encoding="utf-8")

    anchor = hat_manifest["anchor"]
    hats = hat_manifest["hats"]
    source_sha256 = sha256_file(hat_master)
    manifest_sha256 = sha256_file(hat_manifest_path)
    atlas_sha256 = sha256_file(runtime_sheet)
    build_id = hashlib.sha256(
        f"{source_sha256}:{manifest_sha256}:{atlas_sha256}".encode("ascii")
    ).hexdigest()[:16]
    hat_lines = [
        "-- Generated from art/aseprite/hats/hats_manifest.json. Do not edit by hand.",
        "return {",
        '  source = "aseprite_master",',
        f"  source_path = {lua_string(HAT_SOURCE_PATH)},",
        f"  source_sha256 = {lua_string(source_sha256)},",
        f"  manifest_sha256 = {lua_string(manifest_sha256)},",
        f"  atlas_sha256 = {lua_string(atlas_sha256)},",
        f"  build_id = {lua_string(build_id)},",
        '  cache = "fresh",',
        '  render_layer = "world",',
        '  transform = "linked_to_body",',
        f"  expected_count = {len(hats)},",
        f"  anchor = {{ name = {lua_string(anchor['name'])}, x = {anchor['x']}, y = {anchor['y']} }},",
        "  order = { " + ", ".join(lua_string(hat["id"]) for hat in hats) + " },",
        "  menu = { " + ", ".join(lua_string(hat["id"]) for hat in hats if hat.get("menu")) + " },",
        "  by_id = {",
    ]
    for hat in hats:
        sprite = frame(f"hat_{hat['id']}_128")
        opaque_bounds = nontransparent_bounds(load_asset(asset_root, f"hats/{hat['file']}"))
        bounds_lua = ""
        if opaque_bounds is not None:
            x0, y0, x1, y1 = opaque_bounds
            bounds_lua = ", bounds = { x = %d, y = %d, w = %d, h = %d }" % (
                x0,
                y0,
                x1 - x0 + 1,
                y1 - y0 + 1,
            )
        hat_lines.append(
            "    [%s] = { id = %s, label = %s, category = %s, sprite = %d, "
            "asset_key = %s, file = %s, source_tag = %s, source_frame = %d%s },"
            % (
                lua_string(hat["id"]),
                lua_string(hat["id"]),
                lua_string(hat["label"]),
                lua_string(hat["category"]),
                sprite,
                lua_string(f"hat_{hat['id']}_128"),
                lua_string(f"{HAT_RUNTIME_ROOT}/{hat['file']}"),
                lua_string(hat["id"]),
                hat["source_frame"],
                bounds_lua,
            )
        )
    hat_lines.extend(["  },", "}", ""])
    (runtime_dir / "hats_manifest.lua").write_text("\n".join(hat_lines), encoding="utf-8")


def build_sheet(
    asset_root: Path,
    runtime_assets: list[Asset],
    hat_manifest: dict,
    hat_master: Path,
    hat_manifest_path: Path,
) -> None:
    columns = 6
    rows = math.ceil(len(runtime_assets) / columns)
    out = Image(columns * CELL, rows * CELL)
    for idx, asset in enumerate(runtime_assets):
        alpha_paste(out, load_asset(asset_root, asset.rel), (idx % columns) * CELL, (idx // columns) * CELL)
    write_png(asset_root / "sheets/teti_track_master_sheet_128.png", out)
    runtime_sheet = asset_root.parent.parent / "lua/sprites.png"
    write_png(runtime_sheet, out)

    lines = [
        "# Teti Track Master Sheet 128",
        "",
        "- cell size: 128x128",
        "- columns: 6",
        f"- rows: {rows}",
        "- image: `teti_track_master_sheet_128.png`",
        "- runtime copy: `pet-runtime/lua/sprites.png`",
        "",
        "| name | x | y | w | h |",
        "|---|---:|---:|---:|---:|",
    ]
    for idx, asset in enumerate(runtime_assets):
        x = (idx % columns) * CELL
        y = (idx // columns) * CELL
        lines.append(f"| `{asset.name}` | {x} | {y} | {CELL} | {CELL} |")
    lines.append("")
    (asset_root / "sheets/teti_track_master_sheet_128.md").write_text("\n".join(lines), encoding="utf-8")
    write_runtime_manifests(
        asset_root,
        runtime_assets,
        hat_manifest,
        hat_master,
        hat_manifest_path,
        runtime_sheet,
    )


def panel(image: Image, x: int, y: int, w: int, h: int, title: str) -> None:
    fill_rect(image, x, y, w, h, (255, 255, 255, 255))
    stroke_rect(image, x, y, w, h, (181, 204, 200, 255))
    draw_text(image, title, x + 14, y + 14)


def preview_sprite(image: Image, sprite: Image, x: int, y: int) -> None:
    checker(image, x, y, CELL, CELL)
    alpha_paste(image, sprite, x, y)


def build_master_preview(asset_root: Path, hat_preview: list[str]) -> None:
    out = Image.solid(1024, 1024, (235, 242, 242, 255))
    front = load_asset(asset_root, "body/teti_track_front_neutral_128.png")
    side = load_asset(asset_root, "body/teti_track_side_128.png")
    motion = [load_asset(asset_root, rel) for rel in MASTER_MOTION_PREVIEW]
    hats = [load_asset(asset_root, rel) for rel in hat_preview[:6]]
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


def build_previews(asset_root: Path, rebuild_master_preview: bool, hat_manifest: dict) -> None:
    hat_preview = [f"hats/{hat['file']}" for hat in hat_manifest["hats"]]
    build_face_overlay_outputs(asset_root)
    build_track_motion_outputs(asset_root)
    write_png(asset_root / "previews/teti_track_faces_preview_128.png", make_grid(asset_root, FACE_PREVIEW, 3))
    write_png(asset_root / "previews/teti_track_face_overlays_preview_128.png", make_grid(asset_root, [asset.rel for asset in FACE_OVERLAY_ASSETS], 4))
    write_png(asset_root / "previews/teti_track_motion_preview_128.png", make_grid(asset_root, MOTION_PREVIEW, 6))
    write_png(asset_root / "previews/teti_track_track_motion_preview_128.png", make_grid(asset_root, MOTION_PREVIEW, 6))
    write_png(asset_root / "previews/teti_track_hats_preview_128.png", make_hat_grid(asset_root, hat_preview, 6))
    write_png(asset_root / "previews/teti_track_hats_preview_64.png", make_hat_grid_64(asset_root, hat_preview, 6))
    master_preview = asset_root / "previews/teti_track_master_preview_128.png"
    if rebuild_master_preview or not master_preview.exists():
        build_master_preview(asset_root, hat_preview)
    else:
        print(f"preserved curated master preview: {master_preview}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--asset-root", required=True, type=Path)
    parser.add_argument(
        "--hat-manifest",
        type=Path,
        default=Path(__file__).resolve().parents[2] / "art/aseprite/hats/hats_manifest.json",
    )
    parser.add_argument(
        "--hat-master",
        type=Path,
        default=Path(__file__).resolve().parents[2] / HAT_SOURCE_PATH,
    )
    parser.add_argument(
        "--list-hat-exports",
        action="store_true",
        help="print Aseprite source frame and filename pairs for shell export",
    )
    parser.add_argument(
        "--rebuild-master-preview",
        action="store_true",
        help="replace teti_track_master_preview_128.png with the generated fallback overview",
    )
    args = parser.parse_args()

    asset_root = args.asset_root.resolve()
    hat_manifest_path = args.hat_manifest.resolve()
    hat_master = args.hat_master.resolve()
    if not hat_master.is_file():
        raise FileNotFoundError(hat_master)
    hat_manifest = load_hat_manifest(hat_manifest_path)
    if args.list_hat_exports:
        for hat in hat_manifest["hats"]:
            if "source_frame" in hat:
                print(f"{hat['source_frame']}\t{hat['file']}")
        return 0

    build_hat_outputs(asset_root, hat_manifest)
    runtime_assets = CORE_SHEET_ASSETS + TRACK_MOTION_ASSETS + FACE_OVERLAY_ASSETS + hat_assets(hat_manifest)
    build_previews(asset_root, args.rebuild_master_preview, hat_manifest)
    build_sheet(asset_root, runtime_assets, hat_manifest, hat_master, hat_manifest_path)
    print(f"wrote previews and sheets under {asset_root}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
