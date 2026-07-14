#!/usr/bin/env python3
"""Generate original 32x32 pixel Tokcat sprite frames (stdlib only).

v2 art: chibi proportions, rounder head, cleaner silhouette, softer face.
"""

from __future__ import annotations

import json
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "App" / "Resources" / "Sprites" / "TokcatPixel"
SIZE = 32

# Palette (Art Bible)
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
TN = (90, 110, 220, 255)


def blank():
    return [[TR for _ in range(SIZE)] for _ in range(SIZE)]


def setp(px, x, y, c):
    if 0 <= x < SIZE and 0 <= y < SIZE:
        px[y][x] = c


def fill_rect(px, x0, y0, x1, y1, c):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            setp(px, x, y, c)


def hline(px, x0, x1, y, c):
    for x in range(x0, x1 + 1):
        setp(px, x, y, c)


def vline(px, x, y0, y1, c):
    for y in range(y0, y1 + 1):
        setp(px, x, y, c)


def disc(px, cx, cy, r, c, outline=False):
    rr = r * r
    for y in range(cy - r, cy + r + 1):
        for x in range(cx - r, cx + r + 1):
            d = (x - cx) * (x - cx) + (y - cy) * (y - cy)
            if d <= rr:
                if outline and d > (r - 1) * (r - 1):
                    setp(px, x, y, O)
                else:
                    setp(px, x, y, c)


def oval(px, cx, cy, rx, ry, c):
    for y in range(cy - ry, cy + ry + 1):
        for x in range(cx - rx, cx + rx + 1):
            nx = (x - cx) / max(1, rx)
            ny = (y - cy) / max(1, ry)
            if nx * nx + ny * ny <= 1.05:
                setp(px, x, y, c)


def draw_base_cat(
    px,
    *,
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
    rest=False,
    lean=0,
):
    """Cute chibi sit-cat. y grows downward. Round head-forward proportions."""
    hx = head_dx + lean + body_dx
    hy = head_dy + body_dy + breath + (1 if rest else 0)
    by = body_dy
    bx = body_dx

    # --- Soft ground contact (no hard shadow plate) ---
    # --- Tail (simple curve, right side) ---
    tail_pts = [
        (22 + bx, 21 + by, FA), (23 + bx, 20 + by, FA), (24 + bx, 19 + by, FA),
        (25 + bx, 18 + by, FA), (26 + bx, 17 + by, FA), (26 + bx, 16 + by, FA),
        (25 + bx, 15 + by, FA),
        (23 + bx, 21 + by, O), (24 + bx, 20 + by, O), (25 + bx, 19 + by, O),
        (26 + bx, 18 + by, O), (27 + bx, 17 + by, O), (27 + bx, 16 + by, O),
        (26 + bx, 15 + by, O), (25 + bx, 14 + by, O),
    ]
    if paw_phase in (1, 2):
        # slight tail flick
        tail_pts = [
            (22 + bx, 21 + by, FA), (23 + bx, 21 + by, FA), (24 + bx, 20 + by, FA),
            (25 + bx, 19 + by, FA), (26 + bx, 18 + by, FA), (27 + bx, 18 + by, FA),
            (23 + bx, 22 + by, O), (24 + bx, 21 + by, O), (25 + bx, 20 + by, O),
            (26 + bx, 19 + by, O), (27 + bx, 19 + by, O), (28 + bx, 18 + by, O),
        ]
    for x, y, c in tail_pts:
        setp(px, x, y, c)

    # --- Body (round loaf / sit) ---
    # Main body oval
    for y in range(16 + by, 27 + by):
        for x in range(8 + bx, 24 + bx):
            # rounded body mask
            nx = (x - (15.5 + bx)) / 7.6
            ny = (y - (21 + by)) / 5.2
            if nx * nx + ny * ny <= 1.0:
                # lighter top, warmer bottom
                setp(px, x, y, FL if y < 22 + by else FM)

    # belly
    for y in range(20 + by, 25 + by):
        for x in range(11 + bx, 20 + bx):
            nx = (x - (15.5 + bx)) / 4.4
            ny = (y - (22.2 + by)) / 2.4
            if nx * nx + ny * ny <= 1.0:
                setp(px, x, y, SD)

    # body outline (ring)
    for y in range(15 + by, 28 + by):
        for x in range(7, 25):
            nx = (x - 15.5) / 7.9
            ny = (y - (21 + by)) / 5.5
            d = nx * nx + ny * ny
            if 0.86 <= d <= 1.08 and px[y][x][3] != 0:
                # only edge of filled body
                pass
    # cleaner outline pass on body perimeter
    for y in range(16 + by, 27 + by):
        for x in range(8 + bx, 24 + bx):
            if not (0 <= x < SIZE) or px[y][x][3] == 0:
                continue
            # if neighbor empty -> outline
            for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                xx, yy = x + dx, y + dy
                if not (0 <= xx < SIZE and 0 <= yy < SIZE) or px[yy][xx][3] == 0:
                    # mark edge later by painting outline on empty adjacent
                    if 0 <= xx < SIZE and 0 <= yy < SIZE and px[yy][xx][3] == 0:
                        setp(px, xx, yy, O)

    # feet (tiny rounded paws under body)
    fill_rect(px, 10 + bx, 26 + by, 13 + bx, 27 + by, FL)
    fill_rect(px, 18 + bx, 26 + by, 21 + bx, 27 + by, FL)
    hline(px, 10 + bx, 13 + bx, 28 + by, O)
    hline(px, 18 + bx, 21 + bx, 28 + by, O)
    setp(px, 9 + bx, 27 + by, O)
    setp(px, 14 + bx, 27 + by, O)
    setp(px, 17 + bx, 27 + by, O)
    setp(px, 22 + bx, 27 + by, O)

    # --- Front paws ---
    if wave:
        # raised paw
        fill_rect(px, 5 + lean + bx, 15 + by, 8 + lean + bx, 18 + by, FL)
        hline(px, 5 + lean + bx, 8 + lean + bx, 14 + by, O)
        hline(px, 5 + lean + bx, 8 + lean + bx, 19 + by, O)
        vline(px, 4 + lean + bx, 15 + by, 18 + by, O)
        vline(px, 9 + lean + bx, 15 + by, 18 + by, O)
        fill_rect(px, 18 + bx, 22 + by, 21 + bx, 24 + by, FL)
        hline(px, 18 + bx, 21 + bx, 25 + by, O)
    elif eat_token:
        fill_rect(px, 12 + bx, 19 + by, 14 + bx, 22 + by, FL)
        fill_rect(px, 17 + bx, 19 + by, 19 + bx, 22 + by, FL)
        setp(px, 15 + bx, 18 + by, TN)
        setp(px, 15 + bx, 17 + by, TH)
        setp(px, 14 + bx, 18 + by, O)
        setp(px, 16 + bx, 18 + by, O)
    elif groom:
        # lick left paw near face
        fill_rect(px, 11 + bx, 14 + by, 14 + bx, 17 + by, FL)
        hline(px, 11 + bx, 14 + bx, 13 + by, O)
        hline(px, 11 + bx, 14 + bx, 18 + by, O)
        vline(px, 10 + bx, 14 + by, 17 + by, O)
        vline(px, 15 + bx, 14 + by, 17 + by, O)
        fill_rect(px, 17 + bx, 22 + by, 20 + bx, 24 + by, FL)
        hline(px, 17 + bx, 20 + bx, 25 + by, O)
    else:
        # tucked front paws (lazy loaf-ish)
        ly = 22 + by - (1 if paw_phase == 1 else 0)
        ry = 22 + by - (1 if paw_phase == 2 else 0)
        if rest:
            ly += 1
            ry += 1
        fill_rect(px, 11 + bx, ly, 14 + bx, ly + 2, FL)
        fill_rect(px, 17 + bx, ry, 20 + bx, ry + 2, FL)
        hline(px, 11 + bx, 14 + bx, ly + 3, O)
        hline(px, 17 + bx, 20 + bx, ry + 3, O)

    # --- Head (big chibi circle) ---
    cx, cy = 15 + hx, 11 + hy
    # fill
    for y in range(cy - 7, cy + 7 + 1):
        for x in range(cx - 8, cx + 8 + 1):
            nx = (x - cx) / 7.4
            ny = (y - cy) / 6.6
            if nx * nx + ny * ny <= 1.0:
                setp(px, x, y, FL if y < cy + 2 else FM)

    # cheeks blush area pre-paint
    if happy:
        setp(px, cx - 5, cy + 1, CK)
        setp(px, cx + 5, cy + 1, CK)
        setp(px, cx - 5, cy + 2, CK)
        setp(px, cx + 5, cy + 2, CK)

    # ears (rounded triangles)
    # left ear
    ear = [
        (cx - 6, cy - 8, O), (cx - 5, cy - 8, O),
        (cx - 7, cy - 7, O), (cx - 6, cy - 7, FA), (cx - 5, cy - 7, FA), (cx - 4, cy - 7, O),
        (cx - 7, cy - 6, O), (cx - 6, cy - 6, IE), (cx - 5, cy - 6, IE), (cx - 4, cy - 6, FA), (cx - 3, cy - 6, O),
        (cx - 7, cy - 5, O), (cx - 6, cy - 5, FA), (cx - 5, cy - 5, FL), (cx - 4, cy - 5, FL), (cx - 3, cy - 5, O),
    ]
    # right ear
    ear += [
        (cx + 5, cy - 8, O), (cx + 6, cy - 8, O),
        (cx + 4, cy - 7, O), (cx + 5, cy - 7, FA), (cx + 6, cy - 7, FA), (cx + 7, cy - 7, O),
        (cx + 3, cy - 6, O), (cx + 4, cy - 6, FA), (cx + 5, cy - 6, IE), (cx + 6, cy - 6, IE), (cx + 7, cy - 6, O),
        (cx + 3, cy - 5, O), (cx + 4, cy - 5, FL), (cx + 5, cy - 5, FL), (cx + 6, cy - 5, FA), (cx + 7, cy - 5, O),
    ]
    for x, y, c in ear:
        setp(px, x, y, c)

    # head outline
    for y in range(cy - 7, cy + 8):
        for x in range(cx - 8, cx + 9):
            if px[y][x][3] == 0:
                continue
            # only head region
            nx = (x - cx) / 7.4
            ny = (y - cy) / 6.6
            if nx * nx + ny * ny > 1.0:
                continue
            for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                xx, yy = x + dx, y + dy
                if 0 <= xx < SIZE and 0 <= yy < SIZE and px[yy][xx][3] == 0:
                    # leave ear pixels alone if already outline/accent
                    setp(px, xx, yy, O)

    # neck blend into body
    fill_rect(px, cx - 4, cy + 5, cx + 4, cy + 7, FL)

    # --- Face ---
    eye_y = cy - 1
    if sleepy:
        hline(px, cx - 4, cx - 2, eye_y, O)
        hline(px, cx + 2, cx + 4, eye_y, O)
        setp(px, cx - 3, eye_y + 1, EY)
        setp(px, cx + 3, eye_y + 1, EY)
    elif blink:
        hline(px, cx - 4, cx - 2, eye_y + 1, O)
        hline(px, cx + 2, cx + 4, eye_y + 1, O)
    else:
        # big round eyes
        fill_rect(px, cx - 4, eye_y, cx - 2, eye_y + 2, EY)
        fill_rect(px, cx + 2, eye_y, cx + 4, eye_y + 2, EY)
        # highlights
        if sad:
            setp(px, cx - 4, eye_y, FL)
            setp(px, cx + 4, eye_y, FL)
            setp(px, cx - 3, eye_y, EH)
            setp(px, cx + 3, eye_y, EH)
        else:
            setp(px, cx - 3, eye_y, EH)
            setp(px, cx + 3, eye_y, EH)
            if happy:
                setp(px, cx - 2, eye_y + 1, EH)
                setp(px, cx + 4, eye_y + 1, EH)
        if hungry:
            setp(px, cx - 3, eye_y + 1, EH)
            setp(px, cx + 3, eye_y + 1, EH)

    # nose (tiny)
    setp(px, cx, cy + 2, NS)
    setp(px, cx - 1, cy + 3, NS)
    setp(px, cx, cy + 3, NS)
    setp(px, cx + 1, cy + 3, NS)

    # mouth
    my = cy + 4
    if mouth == 1:  # open
        setp(px, cx - 1, my, O)
        setp(px, cx, my, MO)
        setp(px, cx + 1, my, O)
        setp(px, cx, my + 1, O)
    elif mouth == 2:  # smile
        setp(px, cx - 2, my, O)
        setp(px, cx - 1, my + 1, O)
        setp(px, cx, my + 1, O)
        setp(px, cx + 1, my + 1, O)
        setp(px, cx + 2, my, O)
    elif mouth == 3:  # sad
        setp(px, cx - 2, my + 1, O)
        setp(px, cx - 1, my, O)
        setp(px, cx, my, O)
        setp(px, cx + 1, my, O)
        setp(px, cx + 2, my + 1, O)
    else:
        # tiny lazy mouth
        setp(px, cx - 1, my, O)
        setp(px, cx + 1, my, O)

    # token mark (hex chip on chest) — brand but smaller/cleaner
    tx, ty = 15 + bx, 19 + by
    setp(px, tx, ty, TK)
    setp(px, tx - 1, ty + 1, TK)
    setp(px, tx, ty + 1, TH)
    setp(px, tx + 1, ty + 1, TK)
    setp(px, tx, ty + 2, TK)
    setp(px, tx, ty - 1, O)
    setp(px, tx - 1, ty, O)
    setp(px, tx + 1, ty, O)

    if sparkle:
        for x, y in ((6, 7), (25, 6), (7, 18), (24, 15), (15, 3)):
            setp(px, x, y, SP)

    if hungry:
        setp(px, 14, 23 + by, O)
        setp(px, 16, 24 + by, O)


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
    path.write_bytes(data)


def save_clip(name: str, frames: list):
    for i, px in enumerate(frames):
        write_png(OUT / f"{name}_{i}.png", px)


def make_idle():
    frames = []
    for breath, blink in [(0, False), (0, False), (1, False), (0, True)]:
        px = blank()
        draw_base_cat(px, breath=breath, blink=blink)
        frames.append(px)
    return frames


def make_working():
    frames = []
    for i, phase in enumerate([0, 1, 0, 2]):
        px = blank()
        draw_base_cat(px, breath=i % 2, paw_phase=phase)
        frames.append(px)
    return frames


def make_happy():
    frames = []
    for breath in [0, 1, 0]:
        px = blank()
        draw_base_cat(px, breath=breath, happy=True, mouth=2)
        frames.append(px)
    return frames


def make_sad():
    frames = []
    for breath in [0, 0, 1]:
        px = blank()
        draw_base_cat(px, breath=breath, sad=True, mouth=3, head_dy=1)
        frames.append(px)
    return frames


def make_sleepy():
    frames = []
    for breath in [0, 1, 1]:
        px = blank()
        draw_base_cat(px, breath=breath, sleepy=True, head_dy=1)
        frames.append(px)
    return frames


def make_hungry():
    frames = []
    for i, breath in enumerate([0, 1, 0]):
        px = blank()
        draw_base_cat(px, breath=breath, hungry=True, mouth=1 if i == 1 else 0)
        frames.append(px)
    return frames


def make_eating():
    frames = []
    for i in range(4):
        px = blank()
        draw_base_cat(
            px,
            breath=i % 2,
            mouth=1 if i % 2 else 0,
            eat_token=True,
            head_dy=1 if i < 3 else 0,
        )
        frames.append(px)
    return frames


def make_level_up():
    frames = []
    for dy, spark in [(0, False), (-1, True), (-2, True), (-1, True), (0, True)]:
        px = blank()
        draw_base_cat(px, body_dy=dy, happy=True, mouth=2, sparkle=spark)
        frames.append(px)
    return frames




def make_rest():
    """Loaf / napping pose — lower energy than sleepy."""
    frames = []
    for i, (breath, blink) in enumerate([(0, False), (1, False), (1, True), (0, False)]):
        px = blank()
        draw_base_cat(px, breath=breath, blink=blink, rest=True, sleepy=(i >= 2), head_dy=1, mouth=0)
        frames.append(px)
    return frames


def make_pace():
    """Slow left-right walk / shift."""
    frames = []
    path = [-2, -1, 0, 1, 2, 1, 0, -1]
    for i, dx in enumerate(path):
        px = blank()
        draw_base_cat(
            px,
            body_dx=dx,
            breath=i % 2,
            paw_phase=(1 if i % 2 == 0 else 2),
            head_dx=0 if abs(dx) < 2 else (1 if dx > 0 else -1),
        )
        frames.append(px)
    return frames


def make_groom():
    """Lick paw / tidy fur."""
    frames = []
    for i in range(4):
        px = blank()
        draw_base_cat(
            px,
            groom=True,
            breath=i % 2,
            head_dy=-1 if i in (1, 2) else 0,
            head_dx=-1 if i % 2 else 0,
            mouth=1 if i in (1, 2) else 0,
        )
        frames.append(px)
    return frames


def make_look_around():
    """Curious head turns left/right."""
    frames = []
    for i, hdx in enumerate([-2, -1, 0, 1, 2, 0]):
        px = blank()
        draw_base_cat(
            px,
            head_dx=hdx,
            breath=0 if i % 2 == 0 else 1,
            blink=(i == 5),
            mouth=0,
        )
        frames.append(px)
    return frames

def make_interact():
    frames = []
    for i in range(3):
        px = blank()
        draw_base_cat(
            px,
            wave=True,
            happy=True,
            mouth=2,
            head_dx=0 if i != 1 else 1,
            breath=i % 2,
        )
        frames.append(px)
    return frames


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    clips = {
        "idle": {"frames": 4, "fps": 6, "loop": True},
        "working": {"frames": 4, "fps": 8, "loop": True},
        "happy": {"frames": 3, "fps": 6, "loop": True},
        "sad": {"frames": 3, "fps": 5, "loop": True},
        "sleepy": {"frames": 3, "fps": 4, "loop": True},
        "hungry": {"frames": 3, "fps": 5, "loop": True},
        "rest": {"frames": 4, "fps": 3, "loop": True},
        "pace": {"frames": 8, "fps": 5, "loop": True},
        "groom": {"frames": 4, "fps": 4, "loop": False},
        "look_around": {"frames": 6, "fps": 4, "loop": False},
        "eating": {"frames": 4, "fps": 8, "loop": False},
        "level_up": {"frames": 5, "fps": 10, "loop": False},
        "interact": {"frames": 3, "fps": 8, "loop": False},
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
        "eating": make_eating,
        "level_up": make_level_up,
        "interact": make_interact,
    }
    for name, maker in makers.items():
        frames = maker()
        assert len(frames) == clips[name]["frames"], (name, len(frames))
        save_clip(name, frames)
        print(f"wrote {name} x{len(frames)}")

    manifest = {
        "name": "Tokcat Pixel",
        "version": 3,
        "frameSize": SIZE,
        "displayScale": 4,
        "clips": clips,
    }
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"done → {OUT}")


if __name__ == "__main__":
    main()
