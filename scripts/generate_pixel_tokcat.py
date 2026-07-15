#!/usr/bin/env python3
"""Generate original 32x32 pixel Tokcat sprite frames (stdlib only).

v4 art: chibi proportions + Codex-aligned situation clips, rounder head, cleaner silhouette, softer face.
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



# Extra props / pose colors
DESK = (74, 58, 72, 255)
DESK2 = (110, 88, 98, 255)
SCREEN = (56, 72, 110, 255)
SCREEN_LIT = (130, 190, 255, 255)
KEY = (90, 96, 120, 255)
BOWL = (180, 120, 90, 255)
ZZZ = (160, 170, 210, 255)


def draw_oval(px, cx, cy, rx, ry, c, y_split=None, c2=None):
    for y in range(int(cy - ry - 1), int(cy + ry + 2)):
        for x in range(int(cx - rx - 1), int(cx + rx + 2)):
            if not (0 <= x < SIZE and 0 <= y < SIZE):
                continue
            nx = (x - cx) / max(0.5, rx)
            ny = (y - cy) / max(0.5, ry)
            if nx * nx + ny * ny <= 1.0:
                col = c2 if (y_split is not None and c2 is not None and y >= y_split) else c
                setp(px, x, y, col)


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


def draw_face(px, cx, cy, *, blink=False, sleepy=False, happy=False, sad=False,
              hungry=False, mouth=0, failed=False, review=False, think=False, waiting=False):
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
        fill_rect(px, cx - 4, eye_y, cx - 2, eye_y + 2, EY)
        fill_rect(px, cx + 2, eye_y, cx + 4, eye_y + 2, EY)
        if sad or failed:
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
        if review or think:
            setp(px, cx - 3, eye_y + 1, EY)
            setp(px, cx + 3, eye_y + 1, EY)
        if waiting:
            setp(px, cx - 3, eye_y - 1, EH)
            setp(px, cx + 3, eye_y - 1, EH)

    setp(px, cx, cy + 2, NS)
    setp(px, cx - 1, cy + 3, NS)
    setp(px, cx, cy + 3, NS)
    setp(px, cx + 1, cy + 3, NS)

    my = cy + 4
    if mouth == 1:
        setp(px, cx - 1, my, O); setp(px, cx, my, MO); setp(px, cx + 1, my, O); setp(px, cx, my + 1, O)
    elif mouth == 2:
        setp(px, cx - 2, my, O); setp(px, cx - 1, my + 1, O); setp(px, cx, my + 1, O)
        setp(px, cx + 1, my + 1, O); setp(px, cx + 2, my, O)
    elif mouth == 3:
        setp(px, cx - 2, my + 1, O); setp(px, cx - 1, my, O); setp(px, cx, my, O)
        setp(px, cx + 1, my, O); setp(px, cx + 2, my + 1, O)
    else:
        setp(px, cx - 1, my, O); setp(px, cx + 1, my, O)

    if happy:
        setp(px, cx - 5, cy + 1, CK); setp(px, cx + 5, cy + 1, CK)
        setp(px, cx - 5, cy + 2, CK); setp(px, cx + 5, cy + 2, CK)
    if failed:
        setp(px, cx - 5, eye_y + 3, (120, 170, 220, 255))
        setp(px, cx - 5, eye_y + 4, (120, 170, 220, 255))
        setp(px, cx - 4, eye_y - 1, O)
        setp(px, cx + 4, eye_y - 1, O)


def draw_ears(px, cx, cy):
    pts = [
        (cx - 6, cy - 8, O), (cx - 5, cy - 8, O),
        (cx - 7, cy - 7, O), (cx - 6, cy - 7, FA), (cx - 5, cy - 7, FA), (cx - 4, cy - 7, O),
        (cx - 7, cy - 6, O), (cx - 6, cy - 6, IE), (cx - 5, cy - 6, IE), (cx - 4, cy - 6, FA), (cx - 3, cy - 6, O),
        (cx - 7, cy - 5, O), (cx - 6, cy - 5, FA), (cx - 5, cy - 5, FL), (cx - 4, cy - 5, FL), (cx - 3, cy - 5, O),
        (cx + 5, cy - 8, O), (cx + 6, cy - 8, O),
        (cx + 4, cy - 7, O), (cx + 5, cy - 7, FA), (cx + 6, cy - 7, FA), (cx + 7, cy - 7, O),
        (cx + 3, cy - 6, O), (cx + 4, cy - 6, FA), (cx + 5, cy - 6, IE), (cx + 6, cy - 6, IE), (cx + 7, cy - 6, O),
        (cx + 3, cy - 5, O), (cx + 4, cy - 5, FL), (cx + 5, cy - 5, FL), (cx + 6, cy - 5, FA), (cx + 7, cy - 5, O),
    ]
    for x, y, c in pts:
        setp(px, x, y, c)


def draw_token(px, tx, ty):
    setp(px, tx, ty, TK)
    setp(px, tx - 1, ty + 1, TK)
    setp(px, tx, ty + 1, TH)
    setp(px, tx + 1, ty + 1, TK)
    setp(px, tx, ty + 2, TK)
    setp(px, tx, ty - 1, O)
    setp(px, tx - 1, ty, O)
    setp(px, tx + 1, ty, O)


def draw_tail_sit(px, bx, by, flick=False):
    if flick:
        pts = [(22, 21), (23, 21), (24, 20), (25, 19), (26, 18), (27, 18)]
    else:
        pts = [(22, 21), (23, 20), (24, 19), (25, 18), (26, 17), (26, 16), (25, 15)]
    for x, y in pts:
        setp(px, x + bx, y + by, FA)


def draw_workstation(px, phase=0):
    # Compact left desk — keep right edge <= 12 so cat at x~20 stays separate.
    fill_rect(px, 2, 19, 11, 21, DESK2)
    fill_rect(px, 2, 22, 11, 23, DESK)
    hline(px, 1, 12, 18, O)
    hline(px, 1, 12, 24, O)
    vline(px, 1, 19, 23, O)
    vline(px, 12, 19, 23, O)
    vline(px, 3, 24, 27, O)
    vline(px, 10, 24, 27, O)
    fill_rect(px, 3, 20, 9, 21, KEY)
    setp(px, 4, 20, WH)
    setp(px, 6, 21, SCREEN_LIT if phase % 2 == 0 else WH)
    setp(px, 8, 20, WH)
    fill_rect(px, 3, 11, 10, 17, SCREEN)
    fill_rect(px, 4, 12, 9, 16, SCREEN_LIT if phase % 2 == 0 else (90, 140, 210, 255))
    setp(px, 5, 13, WH)
    setp(px, 6, 14, WH)
    setp(px, 7, 15, SP)
    hline(px, 3, 10, 10, O)
    hline(px, 3, 10, 18, O)
    vline(px, 2, 11, 17, O)
    vline(px, 11, 11, 17, O)
    fill_rect(px, 5, 18, 8, 18, DESK)


def draw_bowl(px, x=5, y=24):
    fill_rect(px, x, y, x + 4, y + 1, BOWL)
    hline(px, x - 1, x + 5, y + 2, O)
    hline(px, x, x + 4, y - 1, O)
    setp(px, x + 1, y, TK)
    setp(px, x + 2, y, TH)
    setp(px, x + 3, y, TK)


def draw_head(px, cx, cy, **face_kw):
    draw_oval(px, cx, cy, 6.2, 5.4, FL, y_split=cy + 2, c2=FM)
    draw_ears(px, cx, cy)
    draw_face(px, cx, cy, **face_kw)


def draw_base_cat(
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

    if pose == "desk":
        draw_workstation(px, phase=paw_phase)
        # Cat clearly to the right of the desk with a 1px air gap.
        body_cx, body_cy = 23 + bx, 21 + by + breath
        draw_oval(px, body_cx, body_cy, 4.6, 4.4, FL, y_split=body_cy + 1, c2=FM)
        draw_oval(px, body_cx, body_cy + 1, 2.4, 1.6, SD)
        fill_rect(px, 20 + bx, 25 + by, 22 + bx, 27 + by, FL)
        fill_rect(px, 24 + bx, 25 + by, 26 + bx, 27 + by, FL)
        # one typing paw reaching left toward keyboard (not a body bridge)
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

    if pose == "loaf":
        draw_oval(px, 16 + bx, 24 + by, 9.2, 3.4, FL, y_split=24 + by, c2=FM)
        fill_rect(px, 9 + bx, 25 + by, 12 + bx, 26 + by, FL)
        fill_rect(px, 19 + bx, 25 + by, 22 + bx, 26 + by, FL)
        cx, cy = 12 + bx + head_dx, 19 + by + head_dy + breath
        draw_oval(px, cx, cy, 5.4, 4.4, FL, y_split=cy + 1, c2=FM)
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

    if pose == "side":
        # Long loaf body, head clearly on left, paws tucked, tail on right.
        draw_oval(px, 18 + bx, 24 + by, 8.5, 2.8, FL, y_split=24 + by, c2=FM)
        draw_oval(px, 24 + bx, 24 + by, 3.0, 2.2, FM)
        fill_rect(px, 10 + bx, 24 + by, 13 + bx, 26 + by, FL)
        fill_rect(px, 22 + bx, 25 + by, 26 + bx, 26 + by, FL)
        cx, cy = 7 + bx + head_dx, 20 + by + head_dy + breath
        draw_oval(px, cx, cy, 4.8, 4.2, FL, y_split=cy + 1, c2=FM)
        draw_ears(px, cx, cy)
        draw_face(px, cx, cy + 1, blink=True, sleepy=True, mouth=0)
        for i, (x, y) in enumerate([(24, 21), (25, 20), (26, 19), (26, 18), (25, 17)]):
            setp(px, x + bx, y + by - (1 if breath and i > 2 else 0), FA)
        draw_token(px, 17 + bx, 23 + by)
        setp(px, 12 + bx, 14 + by, ZZZ); setp(px, 13 + bx, 13 + by, ZZZ)
        if paw_phase % 2:
            setp(px, 14 + bx, 12 + by, ZZZ)
        paint_outline(px)
        return

    if pose == "flop":
        draw_oval(px, 17 + bx, 25 + by, 9.0, 2.4, FM)
        draw_oval(px, 17 + bx, 24 + by, 8.0, 1.8, FL)
        fill_rect(px, 6 + bx, 25 + by, 9 + bx, 26 + by, FL)
        fill_rect(px, 23 + bx, 25 + by, 27 + bx, 26 + by, FL)
        cx, cy = 9 + bx + head_dx, 20 + by + head_dy
        draw_oval(px, cx, cy, 4.6, 3.8, FL, y_split=cy + 1, c2=FM)
        draw_ears(px, cx, cy)
        draw_face(px, cx, cy + 1, sad=True, failed=True, mouth=3)
        for x, y in [(23, 24), (24, 25), (25, 26), (26, 26)]:
            setp(px, x + bx, y + by, FA)
        draw_token(px, 17 + bx, 24 + by)
        paint_outline(px)
        return

    if pose == "walk":
        body_cx, body_cy = 15 + bx, 16 + by + breath
        draw_oval(px, body_cx, body_cy, 6.2, 3.4, FL, y_split=body_cy + 1, c2=FM)
        draw_oval(px, body_cx, body_cy + 1, 3.2, 1.4, SD)
        # thin legs (1px wide) with tiny paw pads
        if paw_phase % 2 == 0:
            vline(px, 11 + bx, 20 + by, 27 + by, FL)
            vline(px, 14 + bx, 21 + by, 26 + by, FM)
            vline(px, 18 + bx, 21 + by, 26 + by, FM)
            vline(px, 21 + bx, 20 + by, 27 + by, FL)
            setp(px, 11 + bx, 28 + by, FL); setp(px, 21 + bx, 28 + by, FL)
        else:
            vline(px, 12 + bx, 21 + by, 26 + by, FM)
            vline(px, 15 + bx, 20 + by, 27 + by, FL)
            vline(px, 19 + bx, 20 + by, 27 + by, FL)
            vline(px, 22 + bx, 21 + by, 26 + by, FM)
            setp(px, 15 + bx, 28 + by, FL); setp(px, 19 + bx, 28 + by, FL)
        draw_head(px, 15 + bx + head_dx, 8 + by + head_dy + breath, **face_kw)
        for x, y in [(21, 14), (22, 13), (23, 12), (23, 11), (22, 10)]:
            setp(px, x + bx, y + by, FA)
        draw_token(px, 15 + bx, 16 + by)
        paint_outline(px)
        return

    if pose == "stretch":
        draw_bowl(px, 2, 24)
        # haunches
        draw_oval(px, 22 + bx, 23 + by, 4.0, 3.4, FM)
        fill_rect(px, 21 + bx, 25 + by, 24 + bx, 27 + by, FL)
        # mid torso
        draw_oval(px, 16 + bx, 22 + by, 4.8, 2.8, FL, y_split=22 + by, c2=FM)
        # front reach paws (gap before bowl)
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

    if pose == "crouch":
        draw_oval(px, 16 + bx, 23 + by + breath, 6.4, 3.6, FL, y_split=24 + by, c2=FM)
        fill_rect(px, 12 + bx, 26 + by, 14 + bx, 27 + by, FL)
        fill_rect(px, 18 + bx, 26 + by, 20 + bx, 27 + by, FL)
        # raised paws lower than chin so they don't merge into face
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

    # sit family
    hy = head_dy + by + breath
    hx = head_dx + lean + bx
    draw_tail_sit(px, bx, by, flick=paw_phase in (1, 2) or wave)
    draw_oval(px, 15.5 + bx, 21 + by, 7.2, 5.0, FL, y_split=22 + by, c2=FM)
    draw_oval(px, 15.5 + bx, 22.2 + by, 4.0, 2.2, SD)
    if jump and by <= -2:
        fill_rect(px, 11 + bx, 24 + by, 13 + bx, 25 + by, FL)
        fill_rect(px, 18 + bx, 24 + by, 20 + bx, 25 + by, FL)
    else:
        fill_rect(px, 10 + bx, 26 + by, 13 + bx, 27 + by, FL)
        fill_rect(px, 18 + bx, 26 + by, 21 + bx, 27 + by, FL)

    if wave:
        raise_y = 13 + by
        fill_rect(px, 5 + lean + bx, raise_y, 8 + lean + bx, raise_y + 3, FL)
        hline(px, 5 + lean + bx, 8 + lean + bx, raise_y - 1, O)
        hline(px, 5 + lean + bx, 8 + lean + bx, raise_y + 4, O)
        fill_rect(px, 18 + bx, 22 + by, 21 + bx, 24 + by, FL)
    elif think or review:
        fill_rect(px, 12 + bx, 16 + by, 15 + bx, 19 + by, FL)
        fill_rect(px, 18 + bx, 22 + by, 21 + bx, 24 + by, FL)
    elif eat_token:
        fill_rect(px, 12 + bx, 19 + by, 14 + bx, 22 + by, FL)
        fill_rect(px, 17 + bx, 19 + by, 19 + bx, 22 + by, FL)
        setp(px, 15 + bx, 18 + by, TN)
        setp(px, 15 + bx, 17 + by, TH)
    elif groom:
        fill_rect(px, 11 + bx, 14 + by, 14 + bx, 17 + by, FL)
        fill_rect(px, 17 + bx, 22 + by, 20 + bx, 24 + by, FL)
    else:
        ly = 22 + by - (1 if paw_phase == 1 else 0)
        ry = 22 + by - (1 if paw_phase == 2 else 0)
        fill_rect(px, 11 + bx, ly, 14 + bx, ly + 2, FL)
        fill_rect(px, 17 + bx, ry, 20 + bx, ry + 2, FL)

    cx, cy = 15 + hx, 11 + hy
    draw_oval(px, cx, cy, 6.8, 6.0, FL, y_split=cy + 2, c2=FM)
    draw_ears(px, cx, cy)
    fill_rect(px, cx - 3, cy + 5, cx + 3, cy + 7, FL)
    draw_face(px, cx, cy, **face_kw)
    draw_token(px, 15 + bx, 19 + by)
    paint_outline(px)
    if sparkle:
        for x, y in ((5, 6), (26, 5), (6, 16), (25, 14), (15, 2)):
            setp(px, x, y, SP)


def write_png(path: Path, pixels):
    raw = bytearray()
    for row in pixels:
        raw.append(0)
        for r, g, b, a in row:
            raw.extend((r, g, b, a))

    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0)
    data = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b"")
    path.write_bytes(data)


def save_clip(name: str, frames: list):
    for i, px in enumerate(frames):
        write_png(OUT / f"{name}_{i}.png", px)


def make_idle():
    frames = []
    for b, bl in [(0, False), (0, False), (1, False), (0, True)]:
        px = blank()
        draw_base_cat(px, pose="sit", breath=b, blink=bl)
        frames.append(px)
    return frames


def make_working():
    frames=[]
    for i in range(4):
        px=blank()
        draw_base_cat(px, pose="desk", breath=i%2, paw_phase=i, head_dx=-1, head_dy=1 if i in (1,2) else 0, think=True)
        frames.append(px)
    return frames


def make_happy():
    frames=[]
    for i,b in enumerate([0,1,0]):
        px=blank(); draw_base_cat(px, pose="sit", breath=b, happy=True, mouth=2, body_dy=-1 if i==1 else 0); frames.append(px)
    return frames


def make_sad():
    frames=[]
    for b in [0,0,1]:
        px=blank(); draw_base_cat(px, pose="sit", breath=b, sad=True, mouth=3, head_dy=1, body_dy=1); frames.append(px)
    return frames


def make_sleepy():
    frames=[]
    for i,b in enumerate([0,1,1]):
        px=blank(); draw_base_cat(px, pose="side", breath=b, sleepy=True, paw_phase=i, head_dx=-1 if i==2 else 0); frames.append(px)
    return frames


def make_hungry():
    frames=[]
    for i in range(3):
        px=blank()
        draw_base_cat(px, pose="stretch", breath=i%2, hungry=True, paw_phase=i, head_dx=-1 if i==1 else 0, body_dx=-1 if i==1 else 0)
        frames.append(px)
    return frames


def make_eating():
    frames=[]
    for i in range(4):
        px=blank()
        draw_bowl(px, 6, 24)
        draw_base_cat(px, pose="sit", breath=i%2, mouth=1 if i%2 else 0, eat_token=True, head_dy=2 if i<3 else 1, body_dy=1, head_dx=-1, lean=-1)
        frames.append(px)
    return frames


def make_level_up():
    frames=[]
    for dy, spark in [(0,False),(-1,True),(-4,True),(-2,True),(0,True)]:
        px=blank(); draw_base_cat(px, pose="sit", body_dy=dy, happy=True, mouth=2, sparkle=spark, jump=dy<0); frames.append(px)
    return frames


def make_rest():
    frames=[]
    for i,(b,bl) in enumerate([(0,False),(1,False),(1,True),(0,False)]):
        px=blank(); draw_base_cat(px, pose="loaf", breath=b, blink=bl, sleepy=True, paw_phase=i, head_dx=-1 if i in (1,2) else 0); frames.append(px)
    return frames


def make_pace():
    frames=[]
    for i,dx in enumerate([-2,-1,0,1,2,1,0,-1]):
        px=blank()
        draw_base_cat(px, pose="walk", body_dx=dx, breath=i%2, paw_phase=i, head_dx=0 if abs(dx)<2 else (1 if dx>0 else -1))
        frames.append(px)
    return frames


def make_groom():
    frames=[]
    for i in range(4):
        px=blank()
        draw_base_cat(px, pose="sit", groom=True, breath=i%2, head_dy=-1 if i in (1,2) else 0, head_dx=-1 if i%2 else 0, mouth=1 if i in (1,2) else 0)
        frames.append(px)
    return frames


def make_look_around():
    frames=[]
    for i,hdx in enumerate([-2,-1,0,1,2,0]):
        px=blank(); draw_base_cat(px, pose="sit", head_dx=hdx, breath=i%2, blink=(i==5)); frames.append(px)
    return frames


def make_waiting():
    frames=[]
    for i in range(4):
        px=blank()
        draw_base_cat(px, pose="crouch", breath=i%2, paw_phase=i, lean=1, head_dy=-1 if i==1 else 0, waiting=True, mouth=1 if i==1 else 0, blink=(i==3))
        frames.append(px)
    return frames


def make_failed():
    frames=[]
    for i in range(4):
        px=blank()
        draw_base_cat(px, pose="flop", breath=i%2, failed=True, sad=True, mouth=3, head_dy=0 if i<2 else 1, body_dx=1 if i==2 else 0)
        frames.append(px)
    return frames


def make_review():
    frames=[]
    for i,hdx in enumerate([-1,0,1,0,-1,0]):
        px=blank()
        draw_base_cat(px, pose="desk", breath=i%2, paw_phase=0, head_dx=hdx, head_dy=-1 if i%2==0 else 0, review=True, blink=(i==5))
        frames.append(px)
    return frames


def make_jump():
    frames=[]
    for i,dy in enumerate([1,-1,-5,-3,0]):
        px=blank()
        draw_base_cat(px, pose="sit", body_dy=dy, jump=dy<0, happy=True, mouth=2, breath=0 if dy>=0 else 1, sparkle=i in (2,3), paw_phase=1 if i in (1,2,3) else 0, wave=i in (2,3))
        frames.append(px)
    return frames


def make_wave():
    frames=[]
    for i in range(4):
        px=blank()
        draw_base_cat(px, pose="sit", wave=True, happy=True, mouth=2, lean=0 if i%2==0 else 1, head_dx=0 if i%2==0 else 1, breath=i%2, body_dy=-1 if i in (1,2) else 0)
        frames.append(px)
    return frames


def make_interact():
    frames=[]
    for i in range(3):
        px=blank()
        draw_base_cat(px, pose="sit", wave=True, happy=True, mouth=2, head_dx=0 if i!=1 else 1, breath=i%2, lean=1 if i==1 else 0, body_dy=-1 if i==1 else 0)
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
        "waiting": {"frames": 4, "fps": 4, "loop": True},
        "failed": {"frames": 4, "fps": 5, "loop": True},
        "review": {"frames": 6, "fps": 5, "loop": True},
        "jump": {"frames": 5, "fps": 10, "loop": False},
        "wave": {"frames": 4, "fps": 7, "loop": False},
        "eating": {"frames": 4, "fps": 8, "loop": False},
        "level_up": {"frames": 5, "fps": 10, "loop": False},
        "interact": {"frames": 3, "fps": 8, "loop": False},
    }
    makers = {
        "idle": make_idle, "working": make_working, "happy": make_happy, "sad": make_sad,
        "sleepy": make_sleepy, "hungry": make_hungry, "rest": make_rest, "pace": make_pace,
        "groom": make_groom, "look_around": make_look_around, "waiting": make_waiting,
        "failed": make_failed, "review": make_review, "jump": make_jump, "wave": make_wave,
        "eating": make_eating, "level_up": make_level_up, "interact": make_interact,
    }
    for name, maker in makers.items():
        frames = maker()
        assert len(frames) == clips[name]["frames"], (name, len(frames))
        save_clip(name, frames)
        print(f"wrote {name} x{len(frames)}")
    manifest = {
        "name": "Tokcat Pixel",
        "version": 7,
        "frameSize": SIZE,
        "displayScale": 4,
        "clips": clips,
        "notes": "v7 refined multi-silhouette poses (cleaner desk/loaf/side/walk/stretch)",
    }
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"done → {OUT}")


if __name__ == "__main__":
    main()
