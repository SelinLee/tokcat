#!/usr/bin/env python3
"""Edge-only background remove; solidify ONLY interior whites (not outer matte).

Why previous versions kept a white border:
  AI frames are drawn on white. Anti-aliased silhouette pixels are already a mix of
  character color + white. Forcing those edge pixels to alpha=255 freezes the white
  contamination into RGB → visible white ring. Early "middle transparent" builds
  avoided this by never solidifying the outer rim.

Correct rule:
  - remove border-connected white background
  - solidify interior whites (ears / eyes / glasses / paper)
  - leave / clear pale outer-rim matte; then apply soft AA
"""
from __future__ import annotations

import base64
import json
import sys
from collections import deque
from pathlib import Path

import cv2
import numpy as np
from PIL import Image
import importlib.util

ROOT = Path("/Users/lishihao/Claude/tokencat")
PROD = ROOT / "docs/assets/ai_gen_test/m1_v3_full"
TMP = Path("/tmp/tokcat_v3full")


def _flood_near_white(near_white: np.ndarray) -> np.ndarray:
    h, w = near_white.shape
    visit = np.zeros((h, w), dtype=bool)
    q: deque[tuple[int, int]] = deque()

    def seed(y: int, x: int) -> None:
        if near_white[y, x] and not visit[y, x]:
            visit[y, x] = True
            q.append((y, x))

    for x in range(w):
        seed(0, x)
        seed(h - 1, x)
    for y in range(h):
        seed(y, 0)
        seed(y, w - 1)

    while q:
        y, x = q.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and not visit[ny, nx] and near_white[ny, nx]:
                visit[ny, nx] = True
                q.append((ny, nx))
    return visit


def clear_bg_edge_only(arr: np.ndarray) -> np.ndarray:
    """Remove border white bg; solidify only morphologically-interior coverage."""
    rgba = arr.copy()
    h, w = rgba.shape[:2]
    rgb = rgba[:, :, :3].astype(np.int16)
    a = rgba[:, :, 3]
    lum = rgb.mean(axis=2)
    sat = rgb.max(axis=2) - rgb.min(axis=2)

    near_white = (
        (rgb[:, :, 0] >= 242)
        & (rgb[:, :, 1] >= 242)
        & (rgb[:, :, 2] >= 242)
        & (a > 0)
    )
    ink = ((lum < 225) | (sat > 22)) & (a > 10)
    ink_u8 = ink.astype(np.uint8) * 255

    # Protect whites enclosed by / next to ink (ears, eyes, lenses, paper).
    k_protect = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (21, 21))
    protect = cv2.dilate(ink_u8, k_protect, iterations=2) > 0
    k_close = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (9, 9))
    closed = cv2.morphologyEx(ink_u8, cv2.MORPH_CLOSE, k_close, iterations=2)
    inv = cv2.bitwise_not(closed)
    mask = np.zeros((h + 2, w + 2), np.uint8)
    for pt in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):
        m = mask.copy()
        cv2.floodFill(inv, m, pt, 0)
    holes = inv
    silhouette = cv2.bitwise_or(closed, holes) > 0
    protect |= silhouette

    bg = _flood_near_white(near_white)
    bg &= ~protect
    outside = ~protect
    emptyish = (lum >= 248) | (a < 8)
    bg |= outside & emptyish & ~ink

    rgba[bg, 3] = 0
    rgba[bg, 0:3] = 0

    # Remaining coverage after bg removal.
    remain = rgba[:, :, 3] > 0
    remain |= ink & ~bg
    remain_u8 = remain.astype(np.uint8) * 255

    # Scale-aware interior: erode enough that outer white-matte AA stays outside.
    # Raw frames are ~1k px; ~0.8% of max side ≈ outer fringe band.
    erode_px = max(6, int(round(max(h, w) * 0.008)))
    k_erode = cv2.getStructuringElement(
        cv2.MORPH_ELLIPSE, (erode_px * 2 + 1, erode_px * 2 + 1)
    )
    interior = cv2.erode(remain_u8, k_erode, iterations=1) > 0

    # Solidify interior only (ears/eyes/body). Outer rim keeps residual alpha,
    # then pale matte is stripped so white contamination is not frozen.
    rgba[interior & (rgba[:, :, 3] > 5), 3] = 255
    # Force interior whites fully opaque even if previously partial.
    interior_white = (
        interior
        & (rgb[:, :, 0] >= 200)
        & (rgb[:, :, 1] >= 200)
        & (rgb[:, :, 2] >= 200)
        & (a > 0)
        & ~bg
    )
    rgba[interior_white, 3] = 255

    # Outer rim: drop pale desaturated matte (baked character+white AA).
    outer = remain & ~interior & ~bg
    pale = outer & (lum >= 228) & (sat <= 28)
    rgba[pale, 3] = 0
    rgba[pale, 0:3] = 0

    # Mild soft alpha on remaining non-pale outer rim by luminance.
    outer2 = (rgba[:, :, 3] > 0) & ~interior
    soft = outer2 & (lum >= 200) & (sat <= 35)
    # Higher luminance → lower alpha (less white plate).
    rgba[soft, 3] = np.clip((255 - (lum[soft] - 200) * 4).astype(np.int16), 30, 200).astype(
        np.uint8
    )

    empty = rgba[:, :, 3] == 0
    rgba[empty, 0:3] = 0
    return rgba


def finalize_128(arr128: np.ndarray) -> np.ndarray:
    """Post-resize: interior-only solidify, strip pale rim, soft AA."""
    a = arr128.copy()
    rgb = a[:, :, :3].astype(np.int16)
    alpha = a[:, :, 3]
    lum = rgb.mean(axis=2)
    sat = rgb.max(axis=2) - rgb.min(axis=2)

    content = (alpha > 12) & ((lum < 250) | (sat > 12) | (alpha > 40))
    content_u8 = content.astype(np.uint8) * 255
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))
    # Interior of 128px sprite: erode 2–3 px so outer matte band is excluded.
    interior = cv2.erode(content_u8, k, iterations=2) > 0

    # Solidify interior coverage + interior whites only.
    a[interior & (alpha > 5), 3] = 255
    interior_white = (
        interior
        & (rgb[:, :, 0] >= 200)
        & (rgb[:, :, 1] >= 200)
        & (rgb[:, :, 2] >= 200)
        & (alpha > 0)
    )
    a[interior_white, 3] = 255

    # Clear pale outer matte (the classic white border source).
    outer = content & ~interior
    pale = outer & (lum >= 215) & (sat <= 30)
    a[pale, 3] = 0
    a[pale, 0:3] = 0

    # Extra peel for near-white connected from transparent.
    spec = importlib.util.spec_from_file_location(
        "tokcat_strip_white_border",
        str(Path(__file__).with_name("strip_white_border.py")),
    )
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(mod)
    a, _ = mod.clean_halo(a, light_thr=210, max_depth=3)
    a, _ = mod.soft_outer_edge(a, outer_r=1.8, max_outer_a=130, bright_cap=160)
    return a


def process(name: str) -> None:
    raw_path = PROD / "raw" / f"{name}.png"
    jp = TMP / f"{name}.json"
    if not raw_path.exists() or raw_path.stat().st_size < 10000:
        data = json.loads(jp.read_text())
        if "error" in data:
            print("ERR", data)
            raise SystemExit(1)
        raw_path.write_bytes(base64.b64decode(data["data"][0]["b64_json"]))

    im = Image.open(raw_path).convert("RGBA")
    arr = clear_bg_edge_only(np.array(im))
    out = Image.fromarray(arr, "RGBA")
    bbox = out.getbbox()
    c = out.crop(bbox) if bbox else out
    pad = int(max(c.size) * 0.06)
    side = max(c.size) + pad * 2
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(c, ((side - c.size[0]) // 2, (side - c.size[1]) // 2 + pad // 3), c)
    f128 = np.array(canvas.resize((128, 128), Image.Resampling.LANCZOS))
    f128 = finalize_128(f128)
    img = Image.fromarray(f128, "RGBA")

    (PROD / "frames128").mkdir(exist_ok=True)
    img.save(PROD / "frames128" / f"{name}.png")

    gear = ROOT / "App/Resources/Sprites/TokcatPixel" / "gear"
    gear.mkdir(exist_ok=True)
    if name.startswith("eq_"):
        img.save(gear / f"{name}.png")
    elif name.startswith("skin_"):
        skin_dir = ROOT / "App/Resources/Sprites/TokcatPixel" / "skins"
        skin_dir.mkdir(exist_ok=True)
        img.save(skin_dir / f"{name}.png")
    else:
        img.save(ROOT / "App/Resources/Sprites/TokcatPixel" / f"{name}.png")
    print("ok", name, raw_path.stat().st_size)


if __name__ == "__main__":
    process(sys.argv[1])
