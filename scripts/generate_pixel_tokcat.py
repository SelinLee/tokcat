#!/usr/bin/env python3
# DEPRECATED: use scripts/generate_hd_tokcat.py (128×128 HD).
"""Generate layered 32×32 Tokcat pixel assets (stdlib only).

v8 architecture
---------------
A) Scene props (desk / bowl) are separate from the cat base frames.
B) Hand-tuned pose templates (5 silhouette families) replace loose oval blobs.
C) Equipment ships as real 32×32 PNG overlays under gear/, authored on the sit
   baseline; runtime offsets them per pose family.

Layout written to App/Resources/Sprites/TokcatPixel/:
  {clip}_{i}.png          base cat frames (no scene props)
  scene_desk.png          workstation (animated phases baked as scene_desk_{i}.png)
  scene_bowl.png
  gear/{item_id}.png      sit-anchored equipment overlays
  gear/{item_id}_{i}.png  optional animated gear frames
  manifest.json
"""

from __future__ import annotations

import json
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "App" / "Resources" / "Sprites" / "TokcatPixel"
GEAR_OUT = OUT / "gear"
SIZE = 32

# ── Art Bible palette ────────────────────────────────────────────────────────
O  = (42, 36, 48, 255)       # outline
FL = (246, 231, 216, 255)    # fur light
FM = (231, 194, 160, 255)    # fur mid
FA = (232, 155, 95, 255)     # accent
IE = (95, 191, 181, 255)     # inner ear
TK = (108, 140, 255, 255)    # token
TH = (183, 198, 255, 255)    # token hi
EY = (30, 26, 36, 255)       # eye
EH = (255, 255, 255, 255)    # eye hi
NS = (212, 114, 138, 255)    # nose
CK = (240, 168, 160, 255)    # cheek
SD = (201, 164, 138, 255)    # shadow fur
SP = (255, 226, 138, 255)    # spark
WH = (255, 255, 255, 255)
TR = (0, 0, 0, 0)
MO = (80, 70, 90, 255)

DESK = (74, 58, 72, 255)
DESK2 = (110, 88, 98, 255)
SCREEN = (56, 72, 110, 255)
SCREEN_LIT = (130, 190, 255, 255)
SCREEN_DIM = (90, 140, 210, 255)
KEY = (90, 96, 120, 255)
BOWL = (180, 120, 90, 255)
ZZZ = (160, 170, 210, 255)

# Gear palette extras
PINK = CK
PURPLE = (120, 100, 190, 255)
GOLD = (255, 210, 110, 255)
TEAL = IE
BLUE = TK
DARK = EY
CREAM = FL


# ── Bitmap helpers ───────────────────────────────────────────────────────────
def blank():
    return [[TR for _ in range(SIZE)] for _ in range(SIZE)]


def setp(px, x, y, c):
    if 0 <= x < SIZE and 0 <= y < SIZE and c[3] > 0:
        px[y][x] = c


def getp(px, x, y):
    if 0 <= x < SIZE and 0 <= y < SIZE:
        return px[y][x]
    return TR


def fill_rect(px, x0, y0, x1, y1, c):
    for y in range(min(y0, y1), max(y0, y1) + 1):
        for x in range(min(x0, x1), max(x0, x1) + 1):
            setp(px, x, y, c)


def hline(px, x0, x1, y, c):
    for x in range(min(x0, x1), max(x0, x1) + 1):
        setp(px, x, y, c)


def vline(px, x, y0, y1, c):
    for y in range(min(y0, y1), max(y0, y1) + 1):
        setp(px, x, y, c)


def disc(px, cx, cy, r, c):
    rr = r * r
    for y in range(cy - r, cy + r + 1):
        for x in range(cx - r, cx + r + 1):
            if (x - cx) * (x - cx) + (y - cy) * (y - cy) <= rr:
                setp(px, x, y, c)


def soft_oval(px, cx, cy, rx, ry, c, y_split=None, c2=None):
    """Filled ellipse with optional two-tone vertical split."""
    for y in range(int(cy - ry - 1), int(cy + ry + 2)):
        for x in range(int(cx - rx - 1), int(cx + rx + 2)):
            if not (0 <= x < SIZE and 0 <= y < SIZE):
                continue
            nx = (x - cx) / max(0.5, rx)
            ny = (y - cy) / max(0.5, ry)
            if nx * nx + ny * ny <= 1.0:
                col = c2 if (y_split is not None and c2 is not None and y >= y_split) else c
                setp(px, x, y, col)


def stamp(dst, src, ox=0, oy=0):
    for y in range(SIZE):
        for x in range(SIZE):
            c = src[y][x]
            if c[3]:
                setp(dst, x + ox, y + oy, c)


def paint_outline(px):
    """Outer-silhouette outline only (no bridges between ears / limbs)."""
    from collections import deque

    exterior = [[False] * SIZE for _ in range(SIZE)]
    q = deque()
    for i in range(SIZE):
        for x, y in ((i, 0), (i, SIZE - 1), (0, i), (SIZE - 1, i)):
            if px[y][x][3] == 0 and not exterior[y][x]:
                exterior[y][x] = True
                q.append((x, y))
    while q:
        x, y = q.popleft()
        for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            xx, yy = x + dx, y + dy
            if 0 <= xx < SIZE and 0 <= yy < SIZE and not exterior[yy][xx] and px[yy][xx][3] == 0:
                exterior[yy][xx] = True
                q.append((xx, yy))

    marks = []
    for y in range(SIZE):
        for x in range(SIZE):
            if px[y][x][3] == 0:
                continue
            for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                xx, yy = x + dx, y + dy
                if 0 <= xx < SIZE and 0 <= yy < SIZE and exterior[yy][xx]:
                    marks.append((xx, yy))
    for x, y in marks:
        setp(px, x, y, O)


def write_png(path: Path, pixels):
    raw = bytearray()
    for row in pixels:
        raw.append(0)
        for r, g, b, a in row:
            raw.extend((r, g, b, a))

    def chunk(tag: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    ihdr = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0)
    data = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


# ── Face / head ──────────────────────────────────────────────────────────────
def draw_ears(px, cx, cy):
    """Pointy ears with teal inner. cy = head center."""
    # left ear
    for dx, dy, c in [
        (-5, -5, FL), (-4, -5, FL), (-6, -4, FL), (-5, -4, FL), (-4, -4, FL),
        (-6, -3, FL), (-5, -3, IE), (-4, -3, FL),
        (-5, -2, FL), (-4, -2, FL),
    ]:
        setp(px, cx + dx, cy + dy, c)
    # right ear + accent tip
    for dx, dy, c in [
        (4, -5, FL), (5, -5, FA), (4, -4, FL), (5, -4, FL), (6, -4, FA),
        (4, -3, FL), (5, -3, IE), (6, -3, FL),
        (4, -2, FL), (5, -2, FL),
    ]:
        setp(px, cx + dx, cy + dy, c)


def draw_face(
    px, cx, cy, *,
    blink=False, sleepy=False, happy=False, sad=False,
    hungry=False, mouth=0, failed=False, review=False, think=False, waiting=False,
):
    eye_y = cy - 1
    if sleepy or failed and blink:
        hline(px, cx - 4, cx - 2, eye_y, O)
        hline(px, cx + 2, cx + 4, eye_y, O)
    elif blink:
        hline(px, cx - 4, cx - 2, eye_y + 1, O)
        hline(px, cx + 2, cx + 4, eye_y + 1, O)
    else:
        # big awake eyes
        fill_rect(px, cx - 4, eye_y, cx - 2, eye_y + 2, EY)
        fill_rect(px, cx + 2, eye_y, cx + 4, eye_y + 2, EY)
        if sad or failed:
            setp(px, cx - 4, eye_y, FL)
            setp(px, cx + 4, eye_y, FL)
            setp(px, cx - 3, eye_y + 1, EH)
            setp(px, cx + 3, eye_y + 1, EH)
            # brow droop
            setp(px, cx - 4, eye_y - 1, O)
            setp(px, cx + 4, eye_y - 1, O)
        elif review or think:
            # focused vertical pupils
            fill_rect(px, cx - 3, eye_y, cx - 3, eye_y + 2, EY)
            fill_rect(px, cx + 3, eye_y, cx + 3, eye_y + 2, EY)
            setp(px, cx - 4, eye_y, FL)
            setp(px, cx + 4, eye_y, FL)
            setp(px, cx - 3, eye_y, EH)
            setp(px, cx + 3, eye_y, EH)
        else:
            setp(px, cx - 3, eye_y, EH)
            setp(px, cx + 3, eye_y, EH)
            if happy:
                setp(px, cx - 2, eye_y + 1, EH)
                setp(px, cx + 2, eye_y + 1, EH)

    # nose
    setp(px, cx, cy + 2, NS)
    # mouth
    if mouth == 1:  # open / eat
        setp(px, cx, cy + 3, MO)
        setp(px, cx - 1, cy + 3, MO)
        setp(px, cx + 1, cy + 3, MO)
    elif mouth == 2:  # happy smile
        setp(px, cx - 1, cy + 3, MO)
        setp(px, cx + 1, cy + 3, MO)
        setp(px, cx, cy + 4, MO)
    elif mouth == 3:  # sad
        setp(px, cx - 1, cy + 4, MO)
        setp(px, cx + 1, cy + 4, MO)
        setp(px, cx, cy + 3, MO)
    else:
        setp(px, cx - 1, cy + 3, MO)
        setp(px, cx + 1, cy + 3, MO)

    if happy:
        setp(px, cx - 5, cy + 2, CK)
        setp(px, cx + 5, cy + 2, CK)
    if hungry:
        setp(px, cx - 5, cy + 1, CK)
        setp(px, cx + 5, cy + 1, CK)
    if failed:
        setp(px, cx - 5, cy + 3, (150, 180, 220, 255))  # tear
        setp(px, cx - 5, cy + 4, (150, 180, 220, 255))
    if waiting:
        setp(px, cx + 5, cy - 2, SP)


def draw_token(px, tx, ty):
    """Hex-ish token mark on chest."""
    setp(px, tx, ty, TK)
    setp(px, tx - 1, ty, TK)
    setp(px, tx + 1, ty, TK)
    setp(px, tx, ty - 1, TH)
    setp(px, tx, ty + 1, TK)


def draw_head(px, cx, cy, **face_kw):
    # rounder chibi head — slightly wider than tall
    soft_oval(px, cx, cy, 6.0, 5.2, FL, y_split=cy + 2, c2=FM)
    # cheek fullness
    setp(px, cx - 6, cy + 1, FL)
    setp(px, cx + 6, cy + 1, FL)
    draw_ears(px, cx, cy)
    draw_face(px, cx, cy, **face_kw)


def draw_tail_sit(px, bx, by, flick=False):
    base = [
        (22, 18), (23, 17), (24, 16), (24, 15), (23, 14),
    ]
    if flick:
        base = [(22, 18), (23, 17), (24, 15), (25, 14), (25, 13)]
    for x, y in base:
        setp(px, x + bx, y + by, FA)


# ── Pose templates (cat only — no scene props) ───────────────────────────────
def draw_cat(
    px,
    *,
    pose="sit",
    breath=0,
    blink=False,
    mouth=0,
    paw_phase=0,
    head_dx=0,
    head_dy=0,
    body_dx=0,
    body_dy=0,
    happy=False,
    sleepy=False,
    sad=False,
    hungry=False,
    sparkle=False,
    wave=False,
    eat_token=False,
    groom=False,
    lean=0,
    waiting=False,
    failed=False,
    review=False,
    jump=False,
    think=False,
):
    bx, by = body_dx, body_dy
    face_kw = dict(
        blink=blink, sleepy=sleepy, happy=happy, sad=sad, hungry=hungry,
        mouth=mouth, failed=failed, review=review or think, think=think, waiting=waiting,
    )

    # ── desk: cat on the right (workstation is a scene layer) ──
    if pose == "desk":
        body_cx, body_cy = 23 + bx, 21 + by + breath
        soft_oval(px, body_cx, body_cy, 4.4, 4.2, FL, y_split=body_cy + 1, c2=FM)
        soft_oval(px, body_cx, body_cy + 1.2, 2.2, 1.5, SD)
        # paws
        fill_rect(px, 20 + bx, 25 + by, 22 + bx, 27 + by, FL)
        fill_rect(px, 24 + bx, 25 + by, 26 + bx, 27 + by, FL)
        # typing paw toward keyboard
        if paw_phase % 2 == 0:
            fill_rect(px, 16 + bx, 20 + by, 18 + bx, 21 + by, FL)
            setp(px, 15 + bx, 20 + by, FL)
        else:
            fill_rect(px, 16 + bx, 19 + by, 18 + bx, 20 + by, FL)
            setp(px, 15 + bx, 21 + by, FL)
        for x, y in [(28, 18), (29, 17), (29, 16), (28, 15)]:
            setp(px, x + bx, y + by, FA)
        draw_head(px, 23 + bx + head_dx, 11 + by + head_dy + breath, **face_kw)
        draw_token(px, 23 + bx, 19 + by)
        paint_outline(px)
        return

    # ── loaf ──
    if pose == "loaf":
        soft_oval(px, 16 + bx, 24 + by, 9.0, 3.2, FL, y_split=24 + by, c2=FM)
        fill_rect(px, 9 + bx, 25 + by, 12 + bx, 26 + by, FL)
        fill_rect(px, 19 + bx, 25 + by, 22 + bx, 26 + by, FL)
        cx, cy = 12 + bx + head_dx, 19 + by + head_dy + breath
        soft_oval(px, cx, cy, 5.2, 4.2, FL, y_split=cy + 1, c2=FM)
        draw_ears(px, cx, cy)
        draw_face(px, cx, cy, blink=blink or paw_phase == 2, sleepy=True, mouth=0, happy=happy)
        for x, y in [(24, 23), (25, 22), (25, 21), (24, 20)]:
            setp(px, x + bx, y + by, FA)
        draw_token(px, 17 + bx, 23 + by)
        if paw_phase >= 1:
            setp(px, 19 + bx, 14 + by, ZZZ)
            setp(px, 20 + bx, 13 + by, ZZZ)
        paint_outline(px)
        return

    # ── side (sleepy) ──
    if pose == "side":
        soft_oval(px, 18 + bx, 24 + by, 8.2, 2.6, FL, y_split=24 + by, c2=FM)
        soft_oval(px, 24 + bx, 24 + by, 2.8, 2.0, FM)
        fill_rect(px, 10 + bx, 24 + by, 13 + bx, 26 + by, FL)
        fill_rect(px, 22 + bx, 25 + by, 26 + bx, 26 + by, FL)
        cx, cy = 7 + bx + head_dx, 20 + by + head_dy + breath
        soft_oval(px, cx, cy, 4.6, 4.0, FL, y_split=cy + 1, c2=FM)
        draw_ears(px, cx, cy)
        draw_face(px, cx, cy + 1, blink=True, sleepy=True, mouth=0)
        for i, (x, y) in enumerate([(24, 21), (25, 20), (26, 19), (26, 18), (25, 17)]):
            setp(px, x + bx, y + by - (1 if breath and i > 2 else 0), FA)
        draw_token(px, 17 + bx, 23 + by)
        setp(px, 12 + bx, 14 + by, ZZZ)
        setp(px, 13 + bx, 13 + by, ZZZ)
        if paw_phase % 2:
            setp(px, 14 + bx, 12 + by, ZZZ)
        paint_outline(px)
        return

    # ── flop (failed pancake) ──
    if pose == "flop":
        soft_oval(px, 17 + bx, 25 + by, 9.0, 2.2, FM)
        soft_oval(px, 17 + bx, 24 + by, 8.0, 1.6, FL)
        fill_rect(px, 6 + bx, 25 + by, 9 + bx, 26 + by, FL)
        fill_rect(px, 23 + bx, 25 + by, 27 + bx, 26 + by, FL)
        cx, cy = 9 + bx + head_dx, 20 + by + head_dy
        soft_oval(px, cx, cy, 4.4, 3.6, FL, y_split=cy + 1, c2=FM)
        draw_ears(px, cx, cy)
        draw_face(px, cx, cy + 1, sad=True, failed=True, mouth=3)
        for x, y in [(23, 24), (24, 25), (25, 26), (26, 26)]:
            setp(px, x + bx, y + by, FA)
        draw_token(px, 17 + bx, 24 + by)
        paint_outline(px)
        return

    # ── walk ──
    if pose == "walk":
        body_cx, body_cy = 15 + bx, 16 + by + breath
        soft_oval(px, body_cx, body_cy, 6.0, 3.2, FL, y_split=body_cy + 1, c2=FM)
        soft_oval(px, body_cx, body_cy + 1, 3.0, 1.3, SD)
        if paw_phase % 2 == 0:
            vline(px, 11 + bx, 20 + by, 27 + by, FL)
            vline(px, 14 + bx, 21 + by, 26 + by, FM)
            vline(px, 18 + bx, 21 + by, 26 + by, FM)
            vline(px, 21 + bx, 20 + by, 27 + by, FL)
            setp(px, 11 + bx, 28 + by, FL)
            setp(px, 21 + bx, 28 + by, FL)
        else:
            vline(px, 12 + bx, 21 + by, 26 + by, FM)
            vline(px, 15 + bx, 20 + by, 27 + by, FL)
            vline(px, 19 + bx, 20 + by, 27 + by, FL)
            vline(px, 22 + bx, 21 + by, 26 + by, FM)
            setp(px, 15 + bx, 28 + by, FL)
            setp(px, 19 + bx, 28 + by, FL)
        draw_head(px, 15 + bx + head_dx, 8 + by + head_dy + breath, **face_kw)
        for x, y in [(21, 14), (22, 13), (23, 12), (23, 11), (22, 10)]:
            setp(px, x + bx, y + by, FA)
        draw_token(px, 15 + bx, 16 + by)
        paint_outline(px)
        return

    # ── stretch (hungry reach — bowl is scene layer) ──
    if pose == "stretch":
        soft_oval(px, 22 + bx, 23 + by, 4.0, 3.2, FM)
        fill_rect(px, 21 + bx, 25 + by, 24 + bx, 27 + by, FL)
        soft_oval(px, 16 + bx, 22 + by, 4.6, 2.6, FL, y_split=22 + by, c2=FM)
        fill_rect(px, 9 + bx, 23 + by, 12 + bx, 25 + by, FL)
        setp(px, 8 + bx, 24 + by, FL)
        draw_head(
            px, 10 + bx + head_dx, 16 + by + head_dy + breath,
            hungry=True, mouth=1 if paw_phase % 2 else 0, blink=blink,
        )
        for x, y in [(25, 20), (26, 19), (27, 18), (27, 17)]:
            setp(px, x + bx, y + by, FA)
        draw_token(px, 17 + bx, 21 + by)
        paint_outline(px)
        return

    # ── crouch / waiting ──
    if pose == "crouch":
        soft_oval(px, 16 + bx, 23 + by + breath, 6.2, 3.4, FL, y_split=24 + by, c2=FM)
        fill_rect(px, 12 + bx, 26 + by, 14 + bx, 27 + by, FL)
        fill_rect(px, 18 + bx, 26 + by, 20 + bx, 27 + by, FL)
        ry = 16 + by - (1 if paw_phase % 2 else 0)
        fill_rect(px, 9 + bx, ry, 11 + bx, ry + 3, FL)
        fill_rect(px, 20 + bx, ry, 22 + bx, ry + 3, FL)
        draw_head(
            px, 16 + bx + head_dx + lean, 10 + by + head_dy + breath,
            waiting=True, mouth=1 if paw_phase == 1 else mouth, blink=blink, happy=happy,
        )
        draw_tail_sit(px, bx, by, flick=paw_phase % 2 == 0)
        draw_token(px, 16 + bx, 20 + by)
        paint_outline(px)
        return

    # ── sit family (master) ──
    hy = head_dy + by + breath
    hx = head_dx + lean + bx
    draw_tail_sit(px, bx, by, flick=paw_phase in (1, 2) or wave)

    # body: rounder, denser chibi blob — clearer silhouette than v7
    soft_oval(px, 15.5 + bx, 21 + by, 7.0, 4.8, FL, y_split=22 + by, c2=FM)
    soft_oval(px, 15.5 + bx, 22.2 + by, 3.8, 2.0, SD)

    if jump and by <= -2:
        fill_rect(px, 11 + bx, 24 + by, 13 + bx, 25 + by, FL)
        fill_rect(px, 18 + bx, 24 + by, 20 + bx, 25 + by, FL)
    else:
        fill_rect(px, 10 + bx, 26 + by, 13 + bx, 27 + by, FL)
        fill_rect(px, 18 + bx, 26 + by, 21 + bx, 27 + by, FL)

    if wave:
        raise_y = 13 + by
        fill_rect(px, 5 + lean + bx, raise_y, 8 + lean + bx, raise_y + 3, FL)
        setp(px, 4 + lean + bx, raise_y + 1, FL)
    elif groom:
        fill_rect(px, 10 + bx, 14 + by, 13 + bx, 16 + by, FL)
        setp(px, 12 + bx, 13 + by, FL)
    elif eat_token:
        setp(px, 12 + bx, 18 + by, TK)
        setp(px, 13 + bx, 17 + by, TH)
        setp(px, 11 + bx, 19 + by, TK)

    draw_head(px, 15 + hx, 10 + hy, **face_kw)
    draw_token(px, 15 + bx, 18 + by)

    if sparkle:
        for x, y in [(6, 8), (25, 10), (8, 22), (24, 20), (16, 4)]:
            setp(px, x + bx, y + by, SP)

    paint_outline(px)


# ── Scene layers ─────────────────────────────────────────────────────────────
def make_scene_desk(phase: int = 0) -> list:
    px = blank()
    # desk body
    fill_rect(px, 2, 19, 13, 22, DESK)
    fill_rect(px, 2, 22, 13, 23, DESK2)
    hline(px, 2, 13, 18, O)
    hline(px, 2, 13, 24, O)
    vline(px, 1, 19, 23, O)
    vline(px, 14, 19, 23, O)
    # legs
    vline(px, 3, 24, 28, DESK)
    vline(px, 12, 24, 28, DESK)
    setp(px, 3, 28, O)
    setp(px, 12, 28, O)
    # keyboard
    fill_rect(px, 4, 19, 11, 20, KEY)
    for x in (5, 7, 9):
        setp(px, x, 19, WH if phase % 2 == 0 else SP)
    # monitor
    fill_rect(px, 3, 10, 11, 17, SCREEN)
    lit = SCREEN_LIT if phase % 2 == 0 else SCREEN_DIM
    fill_rect(px, 4, 11, 10, 16, lit)
    setp(px, 5, 12, WH)
    setp(px, 6, 13, WH)
    setp(px, 7, 14, SP)
    # code lines
    hline(px, 5, 9, 15, (80, 120, 180, 255))
    hline(px, 3, 10, 9, O)
    hline(px, 3, 10, 18, O)
    vline(px, 2, 10, 17, O)
    vline(px, 12, 10, 17, O)
    fill_rect(px, 5, 18, 8, 18, DESK)
    paint_outline(px)
    return px


def make_scene_bowl() -> list:
    px = blank()
    # bowl at left-bottom (hungry / eating)
    fill_rect(px, 3, 24, 8, 25, BOWL)
    hline(px, 2, 9, 26, O)
    hline(px, 3, 8, 23, O)
    vline(px, 2, 24, 25, O)
    vline(px, 9, 24, 25, O)
    # token crumbs
    setp(px, 4, 24, TK)
    setp(px, 5, 24, TH)
    setp(px, 6, 24, TK)
    setp(px, 7, 25, TH)
    return px


# ── Clip makers ──────────────────────────────────────────────────────────────
def save_clip(name: str, frames: list):
    for i, px in enumerate(frames):
        write_png(OUT / f"{name}_{i}.png", px)


def frame(pose="sit", **kw):
    px = blank()
    draw_cat(px, pose=pose, **kw)
    return px


def make_idle():
    return [
        frame(breath=0, blink=False),
        frame(breath=0, blink=False),
        frame(breath=1, blink=False),
        frame(breath=0, blink=True),
    ]


def make_working():
    return [
        frame(pose="desk", breath=i % 2, paw_phase=i, head_dx=-1,
              head_dy=1 if i in (1, 2) else 0, think=True)
        for i in range(4)
    ]


def make_happy():
    return [
        frame(breath=b, happy=True, mouth=2, body_dy=-1 if i == 1 else 0)
        for i, b in enumerate([0, 1, 0])
    ]


def make_sad():
    return [
        frame(breath=b, sad=True, mouth=3, head_dy=1, body_dy=1)
        for b in (0, 0, 1)
    ]


def make_sleepy():
    return [
        frame(pose="side", breath=b, sleepy=True, paw_phase=i, head_dx=-1 if i == 2 else 0)
        for i, b in enumerate([0, 1, 1])
    ]


def make_hungry():
    return [
        frame(pose="stretch", breath=i % 2, hungry=True, paw_phase=i,
              head_dx=-1 if i == 1 else 0, body_dx=-1 if i == 1 else 0)
        for i in range(3)
    ]


def make_eating():
    return [
        frame(breath=i % 2, mouth=1 if i % 2 else 0, eat_token=True,
              head_dy=2 if i < 3 else 1, body_dy=1, head_dx=-1, lean=-1)
        for i in range(4)
    ]


def make_level_up():
    frames = []
    for dy, spark in [(0, False), (-1, True), (-4, True), (-2, True), (0, True)]:
        frames.append(frame(body_dy=dy, happy=True, mouth=2, sparkle=spark, jump=dy < 0))
    return frames


def make_rest():
    return [
        frame(pose="loaf", breath=b, blink=bl, sleepy=True, paw_phase=i,
              head_dx=-1 if i in (1, 2) else 0)
        for i, (b, bl) in enumerate([(0, False), (1, False), (1, True), (0, False)])
    ]


def make_pace():
    return [
        frame(pose="walk", body_dx=dx, breath=i % 2, paw_phase=i,
              head_dx=0 if abs(dx) < 2 else (1 if dx > 0 else -1))
        for i, dx in enumerate([-2, -1, 0, 1, 2, 1, 0, -1])
    ]


def make_groom():
    return [
        frame(groom=True, breath=i % 2, head_dy=-1 if i in (1, 2) else 0,
              head_dx=-1 if i % 2 else 0, mouth=1 if i in (1, 2) else 0)
        for i in range(4)
    ]


def make_look_around():
    return [
        frame(head_dx=hdx, breath=i % 2, blink=(i == 5))
        for i, hdx in enumerate([-2, -1, 0, 1, 2, 0])
    ]


def make_waiting():
    return [
        frame(pose="crouch", breath=i % 2, paw_phase=i, lean=1,
              head_dy=-1 if i == 1 else 0, waiting=True,
              mouth=1 if i == 1 else 0, blink=(i == 3))
        for i in range(4)
    ]


def make_failed():
    return [
        frame(pose="flop", breath=i % 2, failed=True, sad=True, mouth=3,
              head_dy=0 if i < 2 else 1, body_dx=1 if i == 2 else 0)
        for i in range(4)
    ]


def make_review():
    return [
        frame(pose="desk", breath=i % 2, paw_phase=0, head_dx=hdx,
              head_dy=-1 if i % 2 == 0 else 0, review=True, blink=(i == 5))
        for i, hdx in enumerate([-1, 0, 1, 0, -1, 0])
    ]


def make_jump():
    return [
        frame(body_dy=dy, jump=dy < 0, happy=True, mouth=2,
              breath=0 if dy >= 0 else 1, sparkle=i in (2, 3),
              paw_phase=1 if i in (1, 2, 3) else 0, wave=i in (2, 3))
        for i, dy in enumerate([1, -1, -5, -3, 0])
    ]


def make_wave():
    return [
        frame(wave=True, happy=True, mouth=2, lean=0 if i % 2 == 0 else 1,
              head_dx=0 if i % 2 == 0 else 1, breath=i % 2,
              body_dy=-1 if i in (1, 2) else 0)
        for i in range(4)
    ]


def make_interact():
    return [
        frame(wave=True, happy=True, mouth=2, head_dx=0 if i != 1 else 1,
              breath=i % 2, lean=1 if i == 1 else 0, body_dy=-1 if i == 1 else 0)
        for i in range(3)
    ]


# ── Gear overlays (sit-anchored full 32×32) ──────────────────────────────────
def gear_blank():
    return blank()


def gset(px, x, y, c):
    setp(px, x, y, c)


def gfill(px, x0, y0, x1, y1, c):
    fill_rect(px, x0, y0, x1, y1, c)


def ghline(px, x0, x1, y, c):
    hline(px, x0, x1, y, c)


def gvline(px, x, y0, y1, c):
    vline(px, x, y0, y1, c)


def grect(px, x0, y0, x1, y1, c):
    ghline(px, x0, x1, y0, c)
    ghline(px, x0, x1, y1, c)
    gvline(px, x0, y0, y1, c)
    gvline(px, x1, y0, y1, c)


# CG bottom-left anchors for sit → convert: y_top = 31 - y_cg
# head (15,24) → top y=7; face (15,19) → top y=12; back (22,14) → top y=17
# held (8,10) → top y=21; aura (15,15) → top y=16
# Gear is drawn in top-left origin (same as base frames).


def make_gear_overlays() -> dict[str, list]:
    """Return item_id → list of frames (usually 1)."""
    out: dict[str, list] = {}

    # ── head ──
    px = gear_blank()
    gfill(px, 9, 6, 11, 7, PINK)
    gfill(px, 13, 6, 15, 7, PINK)
    gset(px, 12, 6, O)
    gset(px, 12, 7, PINK)
    out["eq_pixel_bow"] = [px]

    px = gear_blank()
    gfill(px, 11, 5, 20, 7, CREAM)
    ghline(px, 11, 20, 5, O)
    gset(px, 15, 4, PINK)
    gset(px, 16, 4, PINK)
    out["eq_paper_hat"] = [px]

    px = gear_blank()
    gfill(px, 10, 4, 21, 7, PURPLE)
    gfill(px, 10, 7, 21, 7, O)
    gfill(px, 14, 3, 17, 3, TEAL)
    out["eq_beanie"] = [px]

    px = gear_blank()
    gfill(px, 8, 9, 10, 13, DARK)
    gfill(px, 21, 9, 23, 13, DARK)
    ghline(px, 10, 21, 8, O)
    gset(px, 9, 11, BLUE)
    gset(px, 22, 11, BLUE)
    out["eq_headphones"] = [px]

    px = gear_blank()
    gfill(px, 9, 4, 22, 10, PURPLE)
    gfill(px, 10, 5, 21, 9, DARK)
    ghline(px, 9, 22, 10, O)
    gfill(px, 14, 2, 17, 3, PURPLE)
    out["eq_night_hood"] = [px]

    px = gear_blank()
    gfill(px, 12, 3, 19, 5, GOLD)
    gset(px, 11, 5, GOLD)
    gset(px, 20, 5, GOLD)
    gset(px, 13, 2, SP)
    gset(px, 18, 2, SP)
    gset(px, 15, 1, SP)
    grect(px, 12, 3, 19, 5, O)
    out["eq_debug_crown"] = [px]

    # ── face ──
    px = gear_blank()
    grect(px, 9, 10, 14, 13, DARK)
    grect(px, 17, 10, 22, 13, DARK)
    ghline(px, 14, 17, 11, O)
    gset(px, 11, 11, TEAL)
    gset(px, 19, 11, TEAL)
    out["eq_pixel_shades"] = [px]

    px = gear_blank()
    grect(px, 17, 10, 21, 14, GOLD)
    gset(px, 19, 12, WH)
    gset(px, 21, 9, O)
    out["eq_monocle"] = [px]

    px = gear_blank()
    gfill(px, 13, 16, 18, 19, BLUE)
    gset(px, 14, 17, WH)
    gset(px, 16, 18, SP)
    grect(px, 13, 16, 18, 19, O)
    out["eq_code_badge"] = [px]

    px = gear_blank()
    gfill(px, 9, 9, 22, 14, DARK)
    gfill(px, 10, 10, 14, 13, TEAL)
    gfill(px, 17, 10, 21, 13, TEAL)
    ghline(px, 9, 22, 9, O)
    out["eq_focus_visor"] = [px]

    px = gear_blank()
    grect(px, 9, 9, 14, 14, TEAL)
    grect(px, 17, 9, 22, 14, TEAL)
    ghline(px, 14, 17, 11, TEAL)
    gset(px, 11, 11, WH)
    gset(px, 19, 11, WH)
    out["eq_review_goggles"] = [px]

    # ── back ──
    px = gear_blank()
    gfill(px, 20, 14, 25, 20, FA)
    gfill(px, 21, 15, 24, 19, FM)
    grect(px, 20, 14, 25, 20, O)
    gset(px, 22, 16, TK)
    out["eq_tiny_backpack"] = [px]

    px = gear_blank()
    gfill(px, 10, 15, 21, 16, TEAL)
    gfill(px, 9, 16, 11, 19, TEAL)
    gfill(px, 20, 16, 22, 20, TEAL)
    out["eq_soft_scarf"] = [px]

    px = gear_blank()
    gfill(px, 20, 12, 26, 22, PURPLE)
    gfill(px, 21, 13, 25, 21, (100, 80, 160, 255))
    ghline(px, 20, 26, 12, O)
    out["eq_diff_cape"] = [px]

    px = gear_blank()
    gfill(px, 7, 14, 10, 22, PURPLE)
    gfill(px, 21, 14, 24, 22, PURPLE)
    out["eq_cape"] = [px]

    px = gear_blank()
    gfill(px, 20, 11, 27, 22, BLUE)
    gfill(px, 21, 12, 26, 21, (80, 100, 200, 255))
    gset(px, 24, 14, SP)
    gset(px, 25, 16, WH)
    out["eq_signal_cloak"] = [px]

    # ── held ──
    px = gear_blank()
    gvline(px, 7, 12, 22, O)
    ghline(px, 7, 12, 12, O)
    gset(px, 12, 13, BLUE)
    out["eq_fish_rod"] = [px]

    px = gear_blank()
    gfill(px, 6, 20, 10, 23, GOLD)
    gset(px, 5, 21, PINK)
    gset(px, 8, 21, DARK)
    grect(px, 6, 20, 10, 23, O)
    out["eq_rubber_duck"] = [px]

    px = gear_blank()
    gfill(px, 7, 19, 11, 22, PURPLE)
    grect(px, 7, 19, 11, 22, O)
    gset(px, 9, 20, CREAM)
    out["eq_keycap_charm"] = [px]

    px = gear_blank()
    gfill(px, 6, 19, 14, 22, DARK)
    grect(px, 6, 19, 14, 22, O)
    gset(px, 8, 20, TEAL)
    gset(px, 10, 21, CREAM)
    gset(px, 12, 20, BLUE)
    out["eq_mini_keyboard"] = [px]

    px = gear_blank()
    gfill(px, 6, 18, 10, 23, DARK)
    gfill(px, 7, 19, 9, 22, GOLD)
    gset(px, 8, 20, SP)
    out["eq_night_lantern"] = [px]

    px = gear_blank()
    gvline(px, 8, 12, 22, O)
    gset(px, 9, 13, BLUE)
    gset(px, 7, 14, CREAM)
    out["eq_annotation_quill"] = [px]

    px = gear_blank()
    gfill(px, 7, 18, 13, 23, DARK)
    grect(px, 7, 18, 13, 23, O)
    gset(px, 9, 20, TEAL)
    gset(px, 11, 21, CREAM)
    out["eq_tablet_slate"] = [px]

    # ── aura (2-frame twinkle where useful) ──
    def spark_frame(phase: int):
        p = gear_blank()
        pts = [(6, 12), (25, 13), (15, 4), (8, 22), (24, 20)] if phase == 0 else [
            (7, 14), (24, 11), (16, 5), (9, 21), (23, 19)
        ]
        for x, y in pts:
            gset(p, x, y, SP)
        return p

    out["eq_soft_glow"] = [spark_frame(0), spark_frame(1)]
    out["eq_spark_aura"] = [spark_frame(0), spark_frame(1)]

    px = gear_blank()
    grect(px, 9, 8, 22, 22, BLUE)
    gset(px, 9, 15, WH)
    gset(px, 22, 15, WH)
    out["eq_focus_ring"] = [px]

    frames = []
    for phase in range(4):
        p = gear_blank()
        pts = [(5, 14), (26, 14), (10, 5), (21, 5), (16, 24)]
        for idx, (x, y) in enumerate(pts):
            if idx % 4 == phase:
                gset(p, x, y, PURPLE)
                gset(p, x + 1, y, TH)
        frames.append(p)
    out["eq_compile_aura"] = frames

    px = gear_blank()
    gfill(px, 14, 14, 17, 17, GOLD)
    grect(px, 14, 14, 17, 17, O)
    gset(px, 15, 15, WH)
    out["eq_golden_token"] = [px]

    px = gear_blank()
    gfill(px, 13, 13, 18, 17, GOLD)
    grect(px, 13, 13, 18, 17, O)
    gset(px, 15, 15, WH)
    gset(px, 16, 15, WH)
    gset(px, 12, 18, SP)
    gset(px, 19, 18, SP)
    out["eq_origin_seal"] = [px]

    return out


# ── Main ─────────────────────────────────────────────────────────────────────
def main():
    # Clean previous flat frames only (keep any hand notes if present — we rewrite all)
    OUT.mkdir(parents=True, exist_ok=True)
    GEAR_OUT.mkdir(parents=True, exist_ok=True)

    clips = {
        "idle": {"frames": 4, "fps": 6, "loop": True, "scene": None},
        "working": {"frames": 4, "fps": 8, "loop": True, "scene": "desk"},
        "happy": {"frames": 3, "fps": 6, "loop": True, "scene": None},
        "sad": {"frames": 3, "fps": 5, "loop": True, "scene": None},
        "sleepy": {"frames": 3, "fps": 4, "loop": True, "scene": None},
        "hungry": {"frames": 3, "fps": 5, "loop": True, "scene": "bowl"},
        "rest": {"frames": 4, "fps": 3, "loop": True, "scene": None},
        "pace": {"frames": 8, "fps": 5, "loop": True, "scene": None},
        "groom": {"frames": 4, "fps": 4, "loop": False, "scene": None},
        "look_around": {"frames": 6, "fps": 4, "loop": False, "scene": None},
        "waiting": {"frames": 4, "fps": 4, "loop": True, "scene": None},
        "failed": {"frames": 4, "fps": 5, "loop": True, "scene": None},
        "review": {"frames": 6, "fps": 5, "loop": True, "scene": "desk"},
        "jump": {"frames": 5, "fps": 10, "loop": False, "scene": None},
        "wave": {"frames": 4, "fps": 7, "loop": False, "scene": None},
        "eating": {"frames": 4, "fps": 8, "loop": False, "scene": "bowl"},
        "level_up": {"frames": 5, "fps": 10, "loop": False, "scene": None},
        "interact": {"frames": 3, "fps": 8, "loop": False, "scene": None},
    }

    makers = {
        "idle": make_idle,
        "working": make_working,
        "happy": make_happy,
        "sad": make_sad,
        "sleepy": make_sleepy,
        "hungry": make_hungry,
        "rest": make_rest,
        "pace": make_pace,
        "groom": make_groom,
        "look_around": make_look_around,
        "waiting": make_waiting,
        "failed": make_failed,
        "review": make_review,
        "jump": make_jump,
        "wave": make_wave,
        "eating": make_eating,
        "level_up": make_level_up,
        "interact": make_interact,
    }

    for name, maker in makers.items():
        frames = maker()
        assert len(frames) == clips[name]["frames"], (name, len(frames))
        save_clip(name, frames)
        print(f"base  {name} x{len(frames)}")

    # Scene layers
    write_png(OUT / "scene_desk.png", make_scene_desk(0))
    write_png(OUT / "scene_desk_0.png", make_scene_desk(0))
    write_png(OUT / "scene_desk_1.png", make_scene_desk(1))
    write_png(OUT / "scene_bowl.png", make_scene_bowl())
    print("scene desk/bowl")

    # Gear
    for old in GEAR_OUT.glob("*.png"):
        old.unlink()
    gear = make_gear_overlays()
    gear_manifest = {}
    for item_id, frames in sorted(gear.items()):
        gear_manifest[item_id] = {"frames": len(frames)}
        if len(frames) == 1:
            write_png(GEAR_OUT / f"{item_id}.png", frames[0])
        else:
            for i, fr in enumerate(frames):
                write_png(GEAR_OUT / f"{item_id}_{i}.png", fr)
            # also write base name = frame 0 for simple loaders
            write_png(GEAR_OUT / f"{item_id}.png", frames[0])
        print(f"gear  {item_id} x{len(frames)}")

    # Anchors: top-left origin for docs; runtime uses CG bottom-left.
    # sit head≈(15,7top) → cg y=24; face (15,12)→19; back(22,17)→14; held(8,21)→10; aura(15,16)→15
    anchors = {
        "sit": {"head": [15, 24], "face": [15, 19], "back": [22, 14], "held": [8, 10], "aura": [15, 15], "compact": False},
        "desk": {"head": [23, 20], "face": [23, 17], "back": [28, 15], "held": [15, 12], "aura": [20, 15], "compact": True},
        "loaf": {"head": [12, 12], "face": [12, 11], "back": [24, 10], "held": [9, 8], "aura": [16, 10], "compact": True},
        "side": {"head": [7, 11], "face": [7, 10], "back": [24, 10], "held": [10, 8], "aura": [16, 10], "compact": True},
        "flop": {"head": [9, 11], "face": [9, 10], "back": [24, 8], "held": [6, 7], "aura": [16, 9], "compact": True},
        "walk": {"head": [15, 23], "face": [15, 19], "back": [22, 15], "held": [10, 12], "aura": [15, 15], "compact": False},
        "stretch": {"head": [10, 15], "face": [10, 13], "back": [25, 12], "held": [8, 9], "aura": [16, 12], "compact": True},
        "crouch": {"head": [16, 21], "face": [16, 18], "back": [23, 13], "held": [10, 14], "aura": [16, 15], "compact": False},
    }

    manifest = {
        "name": "Tokcat Pixel",
        "version": 8,
        "frameSize": SIZE,
        "displayScale": 4,
        "layers": {
            "order": ["scene", "base", "gear_back", "gear_held", "gear_head", "gear_face", "gear_aura", "fx"],
            "scene": {
                "desk": {"file": "scene_desk", "animatedFrames": 2},
                "bowl": {"file": "scene_bowl", "animatedFrames": 1},
            },
            "gearSubdir": "gear",
        },
        "anchors": anchors,
        "gear": gear_manifest,
        "clips": clips,
        "notes": (
            "v8 layered: scene props split from base; hand-tuned pose templates; "
            "real gear PNG overlays (sit-anchored, runtime pose offset)"
        ),
    }
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"done → {OUT} (v8 layered)")


if __name__ == "__main__":
    main()
