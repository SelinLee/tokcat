#!/usr/bin/env python3
"""Remove outer light matte halo from Tokcat V3 sprites, then add a light soft edge.

Keeps:
- dark outline / body ink
- interior whites (ears / eyes / glasses / paper)

Removes:
- border-connected light gray / white shell left by solidify-alpha
- soft junk alpha on the outer contour

Then restores a thin non-white soft AA shell so desktop upscale is less jagged.
"""
from __future__ import annotations

import sys
from collections import deque
from pathlib import Path

import numpy as np
import cv2
from PIL import Image

ROOT = Path("/Users/lishihao/Claude/tokencat")
TARGETS = [
    ROOT / "App/Resources/Sprites/TokcatPixel",
    ROOT / "App/Resources/Sprites/TokcatPixel/gear",
    ROOT / "App/Resources/Sprites/TokcatPixel/skins",
    ROOT / "docs/assets/ai_gen_test/m1_v3_full/frames128",
]


def clean_halo(
    arr: np.ndarray,
    light_thr: int = 215,
    max_depth: int = 4,
    sat_thr: int = 30,
) -> tuple[np.ndarray, int]:
    rgba = arr.copy()
    h, w = rgba.shape[:2]
    rgb = rgba[:, :, :3].astype(np.int16)
    alpha = rgba[:, :, 3]
    lum = rgb.mean(axis=2)
    sat = rgb.max(axis=2) - rgb.min(axis=2)

    light = (alpha > 0) & (lum >= light_thr) & (sat <= sat_thr)
    ink = (alpha > 20) & ((lum < light_thr - 15) | (sat > sat_thr))
    transparent = alpha == 0

    touch = np.zeros((h, w), dtype=bool)
    touch[:-1] |= light[1:]
    touch[1:] |= light[:-1]
    touch[:, :-1] |= light[:, 1:]
    touch[:, 1:] |= light[:, :-1]
    seeds = transparent & touch

    visit = np.zeros((h, w), dtype=bool)
    dist = np.full((h, w), 255, dtype=np.uint8)
    q: deque[tuple[int, int]] = deque()

    def push(y: int, x: int, d: int) -> None:
        if visit[y, x]:
            return
        visit[y, x] = True
        dist[y, x] = d
        q.append((y, x))

    for y, x in zip(*np.where(seeds)):
        push(int(y), int(x), 0)
    for x in range(w):
        if light[0, x]:
            push(0, x, 1)
        if light[h - 1, x]:
            push(h - 1, x, 1)
    for y in range(h):
        if light[y, 0]:
            push(y, 0, 1)
        if light[y, w - 1]:
            push(y, w - 1, 1)

    while q:
        y, x = q.popleft()
        d = int(dist[y, x])
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if not (0 <= ny < h and 0 <= nx < w) or visit[ny, nx]:
                continue
            if ink[ny, nx]:
                continue
            if transparent[ny, nx]:
                push(ny, nx, 0)
                continue
            if not light[ny, nx]:
                continue
            nd = 1 if transparent[y, x] else d + 1
            if nd > max_depth:
                continue
            push(ny, nx, nd)

    clear = light & visit & (dist >= 1) & (dist <= max_depth)
    cleared = int(clear.sum())
    rgba[clear, 3] = 0
    rgba[clear, 0:3] = 0

    alpha = rgba[:, :, 3]
    rgb = rgba[:, :, :3].astype(np.int16)
    lum = rgb.mean(axis=2)
    sat = rgb.max(axis=2) - rgb.min(axis=2)
    empty = alpha == 0
    touch = np.zeros_like(empty)
    touch[1:] |= empty[:-1]
    touch[:-1] |= empty[1:]
    touch[:, 1:] |= empty[:, :-1]
    touch[:, :-1] |= empty[:, 1:]
    light2 = (alpha > 0) & (lum >= light_thr) & (sat <= sat_thr) & touch
    soft_junk = touch & (alpha > 0) & (alpha < 48) & (lum >= 170)
    kill = light2 | soft_junk
    cleared += int(kill.sum())
    rgba[kill, 3] = 0
    rgba[kill, 0:3] = 0

    alpha = rgba[:, :, 3]
    rgb = rgba[:, :, :3].astype(np.int16)
    empty = alpha == 0
    touch = np.zeros_like(empty)
    touch[1:] |= empty[:-1]
    touch[:-1] |= empty[1:]
    touch[:, 1:] |= empty[:, :-1]
    touch[:, :-1] |= empty[:, 1:]
    whiteish = (
        (rgb[:, :, 0] >= 200)
        & (rgb[:, :, 1] >= 200)
        & (rgb[:, :, 2] >= 200)
        & (alpha > 10)
    )
    rgba[whiteish & ~touch, 3] = 255

    empty = rgba[:, :, 3] == 0
    rgba[empty, 0:3] = 0
    return rgba, cleared


def soft_outer_edge(
    arr: np.ndarray,
    outer_r: float = 1.6,
    inner_r: float = 0.9,
    max_outer_a: int = 110,
    bright_cap: float = 70,
) -> tuple[np.ndarray, int]:
    """Dark soft-AA shell for black-outline characters.

    Outer fringe uses the *darkest* neighboring solid color (not average),
    so bilinear/desktop upscale does not create a pale halo. Interior whites
    remain fully opaque deeper inside the silhouette.
    """
    rgba = arr.copy()
    a0 = rgba[:, :, 3]
    rgb0 = rgba[:, :, :3].astype(np.float32)

    solid = (a0 >= 175).astype(np.uint8)
    if solid.any():
        k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))
        solid = cv2.morphologyEx(solid, cv2.MORPH_CLOSE, k, iterations=1)
    if not solid.any():
        return rgba, 0

    dist_in = cv2.distanceTransform(solid * 255, cv2.DIST_L2, 5)
    dist_out = cv2.distanceTransform((1 - solid) * 255, cv2.DIST_L2, 5)

    # Darkest-neighbor field for outer shell (erode-like via min filter on solid pixels).
    # Encode solid colors; non-solid as 255 so min picks dark solid.
    big = np.where(solid[:, :, None].astype(bool), rgb0, 255.0).astype(np.float32)
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))
    dark = big.copy()
    steps = max(1, int(np.ceil(outer_r)) + 1)
    for _ in range(steps):
        # morphological min via erode on each channel
        dark = cv2.erode(dark, k)
    # Where min stayed 255, fall back to mean dilate of solid
    solid_rgb = rgb0 * solid[:, :, None]
    solid_w = solid.astype(np.float32)
    meanf = solid_rgb.copy()
    w = solid_w.copy()
    for _ in range(steps):
        meanf = cv2.dilate(meanf, k)
        w = cv2.dilate(w, k)
    mean_rgb = meanf / np.maximum(w[:, :, None], 1e-3)
    use_dark = dark.min(axis=2) < 250
    neigh = np.where(use_dark[:, :, None], dark, mean_rgb)
    # Hard clamp fringe luminance for black-cat outline look.
    lum_n = neigh.mean(axis=2)
    over = lum_n > bright_cap
    if over.any():
        scale = bright_cap / np.maximum(lum_n[over], 1.0)
        neigh[over] *= scale[:, None]

    out_rgb = np.zeros_like(rgb0)
    out_a = np.zeros(solid.shape, dtype=np.float32)
    inside = solid.astype(bool)
    deep = inside & (dist_in >= inner_r)
    near = inside & ~deep
    out_rgb[inside] = rgb0[inside]
    out_a[deep] = 255
    t = np.clip(dist_in[near] / max(inner_r, 1e-3), 0, 1)
    out_a[near] = 230 + t * 25

    # Darken pale contamination on the solid rim itself (baked white matte).
    rim_lum = out_rgb.mean(axis=2)
    pale_rim = near & (rim_lum > 90) & ((out_rgb.max(2) - out_rgb.min(2)) < 40)
    if pale_rim.any():
        # pull toward darkest neighbor
        out_rgb[pale_rim] = neigh[pale_rim]

    outside = (~inside) & (dist_out > 0) & (dist_out <= outer_r)
    cov = np.clip(1.0 - (dist_out / max(outer_r, 1e-3)), 0, 1)
    cov = cov * cov * (3 - 2 * cov)
    out_a[outside] = cov[outside] * float(max_outer_a)
    out_rgb[outside] = neigh[outside]

    out = np.zeros_like(rgba)
    out[:, :, :3] = np.clip(out_rgb, 0, 255).astype(np.uint8)
    out[:, :, 3] = np.clip(out_a, 0, 255).astype(np.uint8)

    interior = dist_in > 1.2
    whiteish = (
        (out[:, :, 0] >= 200)
        & (out[:, :, 1] >= 200)
        & (out[:, :, 2] >= 200)
        & interior
        & (out[:, :, 3] > 10)
    )
    out[whiteish, 3] = 255
    empty = out[:, :, 3] == 0
    out[empty, 0:3] = 0
    changed = int(np.count_nonzero(out != rgba))
    return out, changed


def process_rgba(
    arr: np.ndarray,
    light_thr: int = 215,
    max_depth: int = 4,
    soft: bool = True,
) -> tuple[np.ndarray, int, int]:
    out, cleared = clean_halo(arr, light_thr=light_thr, max_depth=max_depth)
    softened = 0
    if soft:
        out, softened = soft_outer_edge(out)
    return out, cleared, softened


def process_file(
    path: Path,
    light_thr: int = 215,
    max_depth: int = 4,
    soft: bool = True,
) -> tuple[int, int]:
    im = Image.open(path).convert("RGBA")
    out, cleared, softened = process_rgba(
        np.array(im), light_thr=light_thr, max_depth=max_depth, soft=soft
    )
    if cleared or softened:
        Image.fromarray(out, "RGBA").save(path)
    return cleared, softened


def main(argv: list[str]) -> int:
    light_thr = 215
    max_depth = 4
    soft = True
    paths: list[Path] = []
    for arg in argv[1:]:
        if arg.startswith("--thr="):
            light_thr = int(arg.split("=", 1)[1])
        elif arg.startswith("--depth="):
            max_depth = int(arg.split("=", 1)[1])
        elif arg == "--no-soft":
            soft = False
        else:
            paths.append(Path(arg))

    if not paths:
        for folder in TARGETS:
            if folder.is_dir():
                paths.extend(sorted(folder.glob("*.png")))

    total_c = total_s = touched = 0
    for path in paths:
        if not path.is_file():
            continue
        cleared, softened = process_file(
            path, light_thr=light_thr, max_depth=max_depth, soft=soft
        )
        if cleared or softened:
            touched += 1
            total_c += cleared
            total_s += softened
            print(f"ok {path.name} cleared={cleared} soft={softened}", flush=True)
        else:
            print(f"skip {path.name}", flush=True)
    print(
        f"DONE files={touched}/{len(paths)} cleared={total_c} soft={total_s}",
        flush=True,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
