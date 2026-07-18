#!/usr/bin/env python3
"""Generate HD (non-pixel) Tokcat 2D sprites.

128×128 soft illustration frames with anti-aliased shapes (4× supersample).
Keeps the same clip names as the old pixel set so the runtime catalog still works.
Scene props and gear are layered separately.
"""

from __future__ import annotations

import json
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "App" / "Resources" / "Sprites" / "TokcatPixel"
GEAR_OUT = OUT / "gear"
SIZE = 128  # final frame size
SS = 4      # supersample factor
CANVAS = SIZE * SS

# Art Bible palette (RGBA)
O  = (42, 36, 48, 255)
FL = (246, 231, 216, 255)
FM = (231, 194, 160, 255)
FA = (232, 155, 95, 255)
IE = (95, 191, 181, 255)
TK = (108, 140, 255, 255)
TH = (183, 198, 255, 255)
EY = (30, 26, 36, 255)
EH = (255, 255, 255, 255)
NS = (212, 114, 138, 255)
CK = (240, 168, 160, 200)
SD = (201, 164, 138, 255)
SP = (255, 226, 138, 255)
WH = (255, 255, 255, 255)
MO = (80, 70, 90, 255)
DESK = (74, 58, 72, 255)
DESK2 = (110, 88, 98, 255)
SCREEN = (56, 72, 110, 255)
SCREEN_LIT = (130, 190, 255, 255)
KEY = (90, 96, 120, 255)
BOWL = (180, 120, 90, 255)
ZZZ = (160, 170, 210, 220)
PINK = CK
PURPLE = (120, 100, 190, 255)
GOLD = (255, 210, 110, 255)
DARK = EY
CREAM = FL
BLUE = TK
TEAL = IE


def blank(ss=True):
    s = CANVAS if ss else SIZE
    return Image.new("RGBA", (s, s), (0, 0, 0, 0))


def down(img: Image.Image) -> Image.Image:
    return img.resize((SIZE, SIZE), Image.Resampling.LANCZOS)


def sc(v: float) -> float:
    """Map 32-space coords to supersampled canvas."""
    return v * (CANVAS / 32.0)


def ellipse(draw, cx, cy, rx, ry, fill, outline=None, width=0):
    draw.ellipse(
        [cx - rx, cy - ry, cx + rx, cy + ry],
        fill=fill,
        outline=outline,
        width=width,
    )


def rounded_rect(draw, x0, y0, x1, y1, r, fill, outline=None, width=0):
    draw.rounded_rectangle([x0, y0, x1, y1], radius=r, fill=fill, outline=outline, width=width)


def draw_ears(draw, cx, cy):
    # left ear
    pts_l = [
        (cx - sc(5.5), cy - sc(2)),
        (cx - sc(7.2), cy - sc(7.5)),
        (cx - sc(2.5), cy - sc(4.5)),
    ]
    draw.polygon(pts_l, fill=FL)
    # inner
    pts_li = [
        (cx - sc(5.2), cy - sc(2.5)),
        (cx - sc(6.3), cy - sc(6.2)),
        (cx - sc(3.5), cy - sc(4.2)),
    ]
    draw.polygon(pts_li, fill=IE)
    # right ear + accent tip
    pts_r = [
        (cx + sc(5.5), cy - sc(2)),
        (cx + sc(7.5), cy - sc(7.8)),
        (cx + sc(2.5), cy - sc(4.5)),
    ]
    draw.polygon(pts_r, fill=FL)
    draw.polygon(
        [
            (cx + sc(6.0), cy - sc(5.0)),
            (cx + sc(7.2), cy - sc(7.5)),
            (cx + sc(5.5), cy - sc(6.5)),
        ],
        fill=FA,
    )
    pts_ri = [
        (cx + sc(5.2), cy - sc(2.5)),
        (cx + sc(6.4), cy - sc(6.3)),
        (cx + sc(3.5), cy - sc(4.2)),
    ]
    draw.polygon(pts_ri, fill=IE)


def draw_face(draw, cx, cy, *, blink=False, sleepy=False, happy=False, sad=False,
              hungry=False, mouth=0, failed=False, review=False, think=False, waiting=False):
    eye_y = cy - sc(0.8)
    eye_rx, eye_ry = sc(1.35), sc(1.7)
    if sleepy or (failed and blink):
        draw.line([(cx - sc(3.8), eye_y), (cx - sc(1.6), eye_y)], fill=O, width=max(2, int(sc(0.35))))
        draw.line([(cx + sc(1.6), eye_y), (cx + sc(3.8), eye_y)], fill=O, width=max(2, int(sc(0.35))))
    elif blink:
        draw.line([(cx - sc(3.8), eye_y + sc(0.4)), (cx - sc(1.6), eye_y + sc(0.4))], fill=O, width=max(2, int(sc(0.35))))
        draw.line([(cx + sc(1.6), eye_y + sc(0.4)), (cx + sc(3.8), eye_y + sc(0.4))], fill=O, width=max(2, int(sc(0.35))))
    else:
        # soft eyes
        for side in (-1, 1):
            ex = cx + side * sc(2.7)
            if review or think:
                ellipse(draw, ex, eye_y, sc(0.9), sc(1.9), EY)
            elif sad or failed:
                ellipse(draw, ex, eye_y + sc(0.2), eye_rx, eye_ry * 0.85, EY)
            else:
                ellipse(draw, ex, eye_y, eye_rx, eye_ry, EY)
            # highlight
            ellipse(draw, ex - sc(0.35), eye_y - sc(0.55), sc(0.45), sc(0.45), EH)
            if happy:
                ellipse(draw, ex + sc(0.3), eye_y + sc(0.4), sc(0.25), sc(0.25), EH)
        if sad or failed:
            # brows
            draw.arc([cx - sc(4.5), eye_y - sc(2.8), cx - sc(1.2), eye_y + sc(0.5)], 200, 340, fill=O, width=max(2, int(sc(0.3))))
            draw.arc([cx + sc(1.2), eye_y - sc(2.8), cx + sc(4.5), eye_y + sc(0.5)], 200, 340, fill=O, width=max(2, int(sc(0.3))))

    # nose
    ellipse(draw, cx, cy + sc(1.8), sc(0.55), sc(0.4), NS)
    # mouth
    mw = max(2, int(sc(0.28)))
    if mouth == 1:
        ellipse(draw, cx, cy + sc(3.0), sc(1.1), sc(0.85), MO)
    elif mouth == 2:
        draw.arc([cx - sc(1.6), cy + sc(2.0), cx + sc(1.6), cy + sc(4.2)], 20, 160, fill=MO, width=mw)
    elif mouth == 3:
        draw.arc([cx - sc(1.5), cy + sc(2.6), cx + sc(1.5), cy + sc(4.6)], 200, 340, fill=MO, width=mw)
    else:
        draw.arc([cx - sc(1.2), cy + sc(2.4), cx + sc(1.2), cy + sc(3.8)], 30, 150, fill=MO, width=mw)

    if happy or hungry:
        ellipse(draw, cx - sc(4.8), cy + sc(1.5), sc(1.1), sc(0.7), CK)
        ellipse(draw, cx + sc(4.8), cy + sc(1.5), sc(1.1), sc(0.7), CK)
    if failed:
        ellipse(draw, cx - sc(4.5), cy + sc(3.2), sc(0.55), sc(0.9), (150, 180, 220, 230))
    if waiting:
        ellipse(draw, cx + sc(5.2), cy - sc(2.5), sc(0.6), sc(0.6), SP)


def draw_token(draw, tx, ty):
    # soft hex-ish token badge
    r = sc(1.6)
    ellipse(draw, tx, ty, r, r * 0.9, TK)
    ellipse(draw, tx - sc(0.3), ty - sc(0.4), sc(0.55), sc(0.45), TH)


def draw_head(draw, cx, cy, **face_kw):
    # soft two-tone head
    ellipse(draw, cx, cy + sc(0.6), sc(6.4), sc(5.6), FM)
    ellipse(draw, cx, cy - sc(0.2), sc(6.2), sc(5.3), FL)
    # cheek fluff
    ellipse(draw, cx - sc(5.5), cy + sc(1.2), sc(1.8), sc(1.5), FL)
    ellipse(draw, cx + sc(5.5), cy + sc(1.2), sc(1.8), sc(1.5), FL)
    draw_ears(draw, cx, cy)
    draw_face(draw, cx, cy, **face_kw)


def draw_tail(draw, bx, by, flick=False, side="sit"):
    if side == "sit":
        path = [
            (bx + sc(21.5), by + sc(18)),
            (bx + sc(24.5), by + sc(15.5)),
            (bx + sc(26.0), by + sc(12.5 if not flick else 11.0)),
            (bx + sc(24.8), by + sc(10.5 if not flick else 9.0)),
        ]
    else:
        path = [
            (bx + sc(22), by + sc(16)),
            (bx + sc(25), by + sc(14)),
            (bx + sc(27), by + sc(12)),
        ]
    if len(path) >= 2:
        draw.line(path, fill=FA, width=max(4, int(sc(1.4))), joint="curve")
        # tip highlight
        tx, ty = path[-1]
        ellipse(draw, tx, ty, sc(1.0), sc(1.0), FA)


def draw_cat(
    img: Image.Image,
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
    draw = ImageDraw.Draw(img, "RGBA")
    bx, by = sc(body_dx), sc(body_dy)
    br = sc(breath) * 0.6
    face_kw = dict(
        blink=blink, sleepy=sleepy, happy=happy, sad=sad, hungry=hungry,
        mouth=mouth, failed=failed, review=review or think, think=think, waiting=waiting,
    )

    def head_at(hx, hy):
        draw_head(draw, hx + sc(head_dx) + sc(lean) + bx, hy + sc(head_dy) + by + br, **face_kw)

    if pose == "desk":
        # body right side
        ellipse(draw, sc(23) + bx, sc(21) + by + br, sc(4.8), sc(4.6), FM)
        ellipse(draw, sc(23) + bx, sc(20.5) + by + br, sc(4.5), sc(4.2), FL)
        ellipse(draw, sc(23) + bx, sc(22.5) + by, sc(2.4), sc(1.6), SD)
        # feet
        ellipse(draw, sc(21) + bx, sc(26.5) + by, sc(1.6), sc(1.1), FL)
        ellipse(draw, sc(25) + bx, sc(26.5) + by, sc(1.6), sc(1.1), FL)
        # typing paw
        py = sc(20 if paw_phase % 2 == 0 else 19) + by
        ellipse(draw, sc(16.5) + bx, py, sc(2.0), sc(1.2), FL)
        draw_tail(draw, bx + sc(5), by, flick=paw_phase % 2 == 0)
        head_at(sc(23), sc(11))
        draw_token(draw, sc(23) + bx, sc(19) + by)
        return

    if pose == "loaf":
        ellipse(draw, sc(16) + bx, sc(24) + by, sc(9.5), sc(3.6), FM)
        ellipse(draw, sc(16) + bx, sc(23.5) + by, sc(9.0), sc(3.2), FL)
        ellipse(draw, sc(12) + bx + sc(head_dx), sc(19) + by + sc(head_dy) + br, sc(5.4), sc(4.4), FL)
        draw_ears(draw, sc(12) + bx + sc(head_dx), sc(19) + by + sc(head_dy) + br)
        draw_face(draw, sc(12) + bx + sc(head_dx), sc(19) + by + sc(head_dy) + br,
                  blink=blink or paw_phase == 2, sleepy=True, mouth=0, happy=happy)
        draw.line([(sc(24)+bx, sc(23)+by), (sc(26)+bx, sc(20)+by)], fill=FA, width=max(4, int(sc(1.2))))
        draw_token(draw, sc(17) + bx, sc(23) + by)
        if paw_phase >= 1:
            draw.text((sc(19)+bx, sc(12)+by), "z", fill=ZZZ)
        return

    if pose == "side":
        ellipse(draw, sc(18) + bx, sc(24) + by, sc(8.8), sc(3.0), FM)
        ellipse(draw, sc(18) + bx, sc(23.6) + by, sc(8.4), sc(2.6), FL)
        ellipse(draw, sc(7) + bx + sc(head_dx), sc(20) + by + sc(head_dy) + br, sc(4.8), sc(4.2), FL)
        draw_ears(draw, sc(7) + bx + sc(head_dx), sc(20) + by + sc(head_dy) + br)
        draw_face(draw, sc(7) + bx + sc(head_dx), sc(20.5) + by + sc(head_dy) + br, blink=True, sleepy=True, mouth=0)
        draw.line([(sc(24)+bx, sc(22)+by), (sc(27)+bx, sc(18)+by)], fill=FA, width=max(4, int(sc(1.2))))
        draw_token(draw, sc(17) + bx, sc(23) + by)
        return

    if pose == "flop":
        ellipse(draw, sc(17) + bx, sc(25) + by, sc(9.5), sc(2.4), FM)
        ellipse(draw, sc(17) + bx, sc(24.2) + by, sc(8.8), sc(1.9), FL)
        ellipse(draw, sc(9) + bx + sc(head_dx), sc(20) + by + sc(head_dy), sc(4.6), sc(3.8), FL)
        draw_ears(draw, sc(9) + bx + sc(head_dx), sc(20) + by + sc(head_dy))
        draw_face(draw, sc(9) + bx + sc(head_dx), sc(20.5) + by + sc(head_dy), sad=True, failed=True, mouth=3)
        draw_token(draw, sc(17) + bx, sc(24) + by)
        return

    if pose == "walk":
        ellipse(draw, sc(15) + bx, sc(16) + by + br, sc(6.4), sc(3.6), FM)
        ellipse(draw, sc(15) + bx, sc(15.5) + by + br, sc(6.0), sc(3.2), FL)
        ellipse(draw, sc(15) + bx, sc(17.2) + by, sc(3.2), sc(1.4), SD)
        # legs
        if paw_phase % 2 == 0:
            legs = [(11, 20, 28), (14, 21, 26), (18, 21, 26), (21, 20, 28)]
        else:
            legs = [(12, 21, 26), (15, 20, 28), (19, 20, 28), (22, 21, 26)]
        for x, y0, y1 in legs:
            draw.line([(sc(x)+bx, sc(y0)+by), (sc(x)+bx, sc(y1)+by)], fill=FL, width=max(3, int(sc(0.9))))
            ellipse(draw, sc(x)+bx, sc(y1)+by, sc(0.9), sc(0.55), FL)
        head_at(sc(15), sc(8))
        draw.line([(sc(21)+bx, sc(14)+by), (sc(24)+bx, sc(10)+by)], fill=FA, width=max(4, int(sc(1.2))))
        draw_token(draw, sc(15) + bx, sc(16) + by)
        return

    if pose == "stretch":
        ellipse(draw, sc(22) + bx, sc(23) + by, sc(4.2), sc(3.4), FM)
        ellipse(draw, sc(16) + bx, sc(22) + by, sc(5.0), sc(2.8), FL)
        ellipse(draw, sc(10) + bx, sc(24) + by, sc(2.4), sc(1.4), FL)
        head_at(sc(10), sc(16))
        draw.line([(sc(25)+bx, sc(20)+by), (sc(28)+bx, sc(17)+by)], fill=FA, width=max(4, int(sc(1.1))))
        draw_token(draw, sc(17) + bx, sc(21) + by)
        return

    if pose == "crouch":
        ellipse(draw, sc(16) + bx, sc(23) + by + br, sc(6.6), sc(3.8), FM)
        ellipse(draw, sc(16) + bx, sc(22.5) + by + br, sc(6.2), sc(3.4), FL)
        ellipse(draw, sc(13) + bx, sc(27) + by, sc(1.4), sc(0.9), FL)
        ellipse(draw, sc(19) + bx, sc(27) + by, sc(1.4), sc(0.9), FL)
        ry = sc(16 if paw_phase % 2 == 0 else 15) + by
        ellipse(draw, sc(10) + bx, ry, sc(1.6), sc(2.0), FL)
        ellipse(draw, sc(21) + bx, ry, sc(1.6), sc(2.0), FL)
        head_at(sc(16), sc(10))
        draw_tail(draw, bx, by, flick=paw_phase % 2 == 0)
        draw_token(draw, sc(16) + bx, sc(20) + by)
        return

    # sit family (master)
    draw_tail(draw, bx, by, flick=paw_phase in (1, 2) or wave)
    ellipse(draw, sc(15.5) + bx, sc(21.5) + by, sc(7.4), sc(5.2), FM)
    ellipse(draw, sc(15.5) + bx, sc(20.8) + by, sc(7.0), sc(4.8), FL)
    ellipse(draw, sc(15.5) + bx, sc(22.5) + by, sc(4.0), sc(2.2), SD)
    if jump and body_dy <= -2:
        ellipse(draw, sc(12) + bx, sc(25) + by, sc(1.5), sc(1.0), FL)
        ellipse(draw, sc(19) + bx, sc(25) + by, sc(1.5), sc(1.0), FL)
    else:
        ellipse(draw, sc(11.5) + bx, sc(27) + by, sc(1.8), sc(1.1), FL)
        ellipse(draw, sc(19.5) + bx, sc(27) + by, sc(1.8), sc(1.1), FL)

    if wave:
        raise_y = sc(13) + by
        ellipse(draw, sc(6.5) + sc(lean) + bx, raise_y, sc(2.0), sc(2.4), FL)
        ellipse(draw, sc(5.2) + sc(lean) + bx, raise_y - sc(0.5), sc(1.2), sc(1.2), FL)
    elif groom:
        ellipse(draw, sc(11.5) + bx, sc(15) + by, sc(2.0), sc(1.6), FL)
    elif eat_token:
        ellipse(draw, sc(12) + bx, sc(18) + by, sc(1.2), sc(1.0), TK)
        ellipse(draw, sc(12.3) + bx, sc(17.5) + by, sc(0.5), sc(0.4), TH)

    head_at(sc(15), sc(10))
    draw_token(draw, sc(15) + bx, sc(18) + by)

    if sparkle:
        for x, y in [(6, 8), (25, 10), (8, 22), (24, 20), (16, 4)]:
            ellipse(draw, sc(x) + bx, sc(y) + by, sc(0.7), sc(0.7), SP)


def make_scene_desk(phase=0) -> Image.Image:
    img = blank()
    d = ImageDraw.Draw(img, "RGBA")
    # desk body
    rounded_rect(d, sc(2), sc(19), sc(13), sc(23.5), sc(0.6), DESK)
    rounded_rect(d, sc(2), sc(22), sc(13), sc(24), sc(0.3), DESK2)
    # legs
    d.rectangle([sc(3), sc(24), sc(4), sc(28.5)], fill=DESK)
    d.rectangle([sc(11.5), sc(24), sc(12.5), sc(28.5)], fill=DESK)
    # keyboard
    rounded_rect(d, sc(4), sc(19.2), sc(11), sc(20.8), sc(0.3), KEY)
    for i, x in enumerate([5.0, 6.5, 8.0, 9.5]):
        col = WH if (phase + i) % 2 == 0 else SP
        ellipse(d, sc(x), sc(20), sc(0.35), sc(0.25), col)
    # monitor
    rounded_rect(d, sc(3), sc(9.5), sc(11.5), sc(18), sc(0.5), O)
    lit = SCREEN_LIT if phase % 2 == 0 else (90, 140, 210, 255)
    rounded_rect(d, sc(3.6), sc(10.2), sc(10.9), sc(17.2), sc(0.35), lit)
    # code lines
    for i, y in enumerate([12.0, 13.2, 14.4, 15.6]):
        w = 4.5 - i * 0.5
        d.line([(sc(5), sc(y)), (sc(5 + w), sc(y))], fill=WH, width=max(2, int(sc(0.25))))
    d.rectangle([sc(6), sc(18), sc(8.5), sc(19.2)], fill=DESK)
    return down(img)


def make_scene_bowl() -> Image.Image:
    img = blank()
    d = ImageDraw.Draw(img, "RGBA")
    ellipse(d, sc(5.5), sc(25.5), sc(3.2), sc(1.6), BOWL)
    ellipse(d, sc(5.5), sc(24.8), sc(2.6), sc(1.0), (200, 140, 100, 255))
    ellipse(d, sc(4.5), sc(24.5), sc(0.5), sc(0.4), TK)
    ellipse(d, sc(5.5), sc(24.4), sc(0.5), sc(0.4), TH)
    ellipse(d, sc(6.5), sc(24.6), sc(0.5), sc(0.4), TK)
    return down(img)


def frame(pose="sit", **kw) -> Image.Image:
    img = blank()
    draw_cat(img, pose=pose, **kw)
    # mild soft edge for illustration feel (very light)
    out = down(img)
    return out


def save(path: Path, img: Image.Image):
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, "PNG")


def save_clip(name: str, frames: list[Image.Image]):
    for i, fr in enumerate(frames):
        save(OUT / f"{name}_{i}.png", fr)


# ── clips ────────────────────────────────────────────────────────────────────
def make_idle():
    return [frame(breath=b, blink=bl) for b, bl in [(0, False), (0, False), (1, False), (0, True)]]

def make_working():
    return [frame(pose="desk", breath=i % 2, paw_phase=i, head_dx=-1,
                  head_dy=1 if i in (1, 2) else 0, think=True) for i in range(4)]

def make_happy():
    return [frame(breath=b, happy=True, mouth=2, body_dy=-1 if i == 1 else 0)
            for i, b in enumerate([0, 1, 0])]

def make_sad():
    return [frame(breath=b, sad=True, mouth=3, head_dy=1, body_dy=1) for b in (0, 0, 1)]

def make_sleepy():
    return [frame(pose="side", breath=b, sleepy=True, paw_phase=i, head_dx=-1 if i == 2 else 0)
            for i, b in enumerate([0, 1, 1])]

def make_hungry():
    return [frame(pose="stretch", breath=i % 2, hungry=True, paw_phase=i,
                  head_dx=-1 if i == 1 else 0, body_dx=-1 if i == 1 else 0) for i in range(3)]

def make_eating():
    return [frame(breath=i % 2, mouth=1 if i % 2 else 0, eat_token=True,
                  head_dy=2 if i < 3 else 1, body_dy=1, head_dx=-1, lean=-1) for i in range(4)]

def make_level_up():
    return [frame(body_dy=dy, happy=True, mouth=2, sparkle=spark, jump=dy < 0)
            for dy, spark in [(0, False), (-1, True), (-4, True), (-2, True), (0, True)]]

def make_rest():
    return [frame(pose="loaf", breath=b, blink=bl, sleepy=True, paw_phase=i,
                  head_dx=-1 if i in (1, 2) else 0)
            for i, (b, bl) in enumerate([(0, False), (1, False), (1, True), (0, False)])]

def make_pace():
    return [frame(pose="walk", body_dx=dx, breath=i % 2, paw_phase=i,
                  head_dx=0 if abs(dx) < 2 else (1 if dx > 0 else -1))
            for i, dx in enumerate([-2, -1, 0, 1, 2, 1, 0, -1])]

def make_groom():
    return [frame(groom=True, breath=i % 2, head_dy=-1 if i in (1, 2) else 0,
                  head_dx=-1 if i % 2 else 0, mouth=1 if i in (1, 2) else 0) for i in range(4)]

def make_look_around():
    return [frame(head_dx=hdx, breath=i % 2, blink=(i == 5))
            for i, hdx in enumerate([-2, -1, 0, 1, 2, 0])]

def make_waiting():
    return [frame(pose="crouch", breath=i % 2, paw_phase=i, lean=1,
                  head_dy=-1 if i == 1 else 0, waiting=True,
                  mouth=1 if i == 1 else 0, blink=(i == 3)) for i in range(4)]

def make_failed():
    return [frame(pose="flop", breath=i % 2, failed=True, sad=True, mouth=3,
                  head_dy=0 if i < 2 else 1, body_dx=1 if i == 2 else 0) for i in range(4)]

def make_review():
    return [frame(pose="desk", breath=i % 2, paw_phase=0, head_dx=hdx,
                  head_dy=-1 if i % 2 == 0 else 0, review=True, blink=(i == 5))
            for i, hdx in enumerate([-1, 0, 1, 0, -1, 0])]

def make_jump():
    return [frame(body_dy=dy, jump=dy < 0, happy=True, mouth=2,
                  breath=0 if dy >= 0 else 1, sparkle=i in (2, 3),
                  paw_phase=1 if i in (1, 2, 3) else 0, wave=i in (2, 3))
            for i, dy in enumerate([1, -1, -5, -3, 0])]

def make_wave():
    return [frame(wave=True, happy=True, mouth=2, lean=0 if i % 2 == 0 else 1,
                  head_dx=0 if i % 2 == 0 else 1, breath=i % 2,
                  body_dy=-1 if i in (1, 2) else 0) for i in range(4)]

def make_interact():
    return [frame(wave=True, happy=True, mouth=2, head_dx=0 if i != 1 else 1,
                  breath=i % 2, lean=1 if i == 1 else 0, body_dy=-1 if i == 1 else 0)
            for i in range(3)]


# ── gear (HD, sit-anchored in 128 space via 32-space mapping) ─────────────────
def gear_img():
    return blank()


def finalize_gear(img: Image.Image) -> Image.Image:
    return down(img)


def make_gears() -> dict[str, list[Image.Image]]:
    out: dict[str, list[Image.Image]] = {}

    def one(draw_fn):
        img = gear_img()
        d = ImageDraw.Draw(img, "RGBA")
        draw_fn(d)
        return [finalize_gear(img)]

    out["eq_pixel_bow"] = one(lambda d: (
        ellipse(d, sc(10), sc(6.5), sc(1.8), sc(1.1), PINK),
        ellipse(d, sc(14), sc(6.5), sc(1.8), sc(1.1), PINK),
        ellipse(d, sc(12), sc(6.8), sc(0.8), sc(0.8), O),
    ) and None)

    # simpler explicit gear
    def bow():
        img = gear_img(); d = ImageDraw.Draw(img, "RGBA")
        ellipse(d, sc(10), sc(6.5), sc(1.8), sc(1.1), PINK)
        ellipse(d, sc(14), sc(6.5), sc(1.8), sc(1.1), PINK)
        ellipse(d, sc(12), sc(6.8), sc(0.8), sc(0.8), O)
        return [finalize_gear(img)]
    out["eq_pixel_bow"] = bow()

    def paper_hat():
        img = gear_img(); d = ImageDraw.Draw(img, "RGBA")
        d.polygon([(sc(11), sc(7)), (sc(20), sc(7)), (sc(15.5), sc(3.5))], fill=CREAM)
        d.line([(sc(11), sc(7)), (sc(20), sc(7))], fill=O, width=max(2, int(sc(0.3))))
        ellipse(d, sc(15.5), sc(3.2), sc(0.7), sc(0.5), PINK)
        return [finalize_gear(img)]
    out["eq_paper_hat"] = paper_hat()

    def beanie():
        img = gear_img(); d = ImageDraw.Draw(img, "RGBA")
        ellipse(d, sc(15.5), sc(5.5), sc(6.0), sc(3.2), PURPLE)
        rounded_rect(d, sc(10), sc(6), sc(21), sc(8), sc(0.5), O)
        ellipse(d, sc(15.5), sc(3.2), sc(1.4), sc(1.2), TEAL)
        return [finalize_gear(img)]
    out["eq_beanie"] = beanie()

    def headphones():
        img = gear_img(); d = ImageDraw.Draw(img, "RGBA")
        d.arc([sc(8), sc(6), sc(23), sc(18)], 200, 340, fill=O, width=max(3, int(sc(0.7))))
        ellipse(d, sc(9), sc(12), sc(1.8), sc(2.2), DARK)
        ellipse(d, sc(22), sc(12), sc(1.8), sc(2.2), DARK)
        ellipse(d, sc(9), sc(12), sc(0.7), sc(0.9), BLUE)
        ellipse(d, sc(22), sc(12), sc(0.7), sc(0.9), BLUE)
        return [finalize_gear(img)]
    out["eq_headphones"] = headphones()

    def night_hood():
        img = gear_img(); d = ImageDraw.Draw(img, "RGBA")
        ellipse(d, sc(15.5), sc(7), sc(7.5), sc(5.5), PURPLE)
        ellipse(d, sc(15.5), sc(8), sc(6.2), sc(4.2), DARK)
        # face hole soft
        ellipse(d, sc(15.5), sc(10), sc(4.5), sc(3.5), (0, 0, 0, 0))
        return [finalize_gear(img)]
    out["eq_night_hood"] = night_hood()

    def crown():
        img = gear_img(); d = ImageDraw.Draw(img, "RGBA")
        d.polygon([(sc(11), sc(7)), (sc(12.5), sc(3.5)), (sc(15.5), sc(6)),
                   (sc(18.5), sc(3.5)), (sc(20), sc(7))], fill=GOLD)
        for x in (12.5, 15.5, 18.5):
            ellipse(d, sc(x), sc(3.5), sc(0.55), sc(0.55), SP)
        return [finalize_gear(img)]
    out["eq_debug_crown"] = crown()

    def shades():
        img = gear_img(); d = ImageDraw.Draw(img, "RGBA")
        rounded_rect(d, sc(9), sc(10), sc(14), sc(13.5), sc(0.6), DARK)
        rounded_rect(d, sc(17), sc(10), sc(22), sc(13.5), sc(0.6), DARK)
        d.line([(sc(14), sc(11.5)), (sc(17), sc(11.5))], fill=O, width=max(2, int(sc(0.35))))
        ellipse(d, sc(11.5), sc(11.5), sc(0.5), sc(0.5), TEAL)
        ellipse(d, sc(19.5), sc(11.5), sc(0.5), sc(0.5), TEAL)
        return [finalize_gear(img)]
    out["eq_pixel_shades"] = shades()

    def monocle():
        img = gear_img(); d = ImageDraw.Draw(img, "RGBA")
        d.ellipse([sc(17), sc(10), sc(22), sc(15)], outline=GOLD, width=max(3, int(sc(0.45))))
        ellipse(d, sc(19.5), sc(12.2), sc(0.5), sc(0.5), WH)
        d.line([(sc(22), sc(11)), (sc(23), sc(8))], fill=O, width=max(2, int(sc(0.3))))
        return [finalize_gear(img)]
    out["eq_monocle"] = monocle()

    def badge():
        img = gear_img(); d = ImageDraw.Draw(img, "RGBA")
        rounded_rect(d, sc(13), sc(16), sc(18.5), sc(19.5), sc(0.5), BLUE)
        ellipse(d, sc(14.5), sc(17.5), sc(0.4), sc(0.4), WH)
        ellipse(d, sc(16.5), sc(18), sc(0.4), sc(0.4), SP)
        return [finalize_gear(img)]
    out["eq_code_badge"] = badge()

    def visor():
        img = gear_img(); d = ImageDraw.Draw(img, "RGBA")
        rounded_rect(d, sc(9), sc(9), sc(22), sc(14), sc(1.0), DARK)
        rounded_rect(d, sc(10), sc(10), sc(14.5), sc(13), sc(0.4), TEAL)
        rounded_rect(d, sc(16.5), sc(10), sc(21), sc(13), sc(0.4), TEAL)
        return [finalize_gear(img)]
    out["eq_focus_visor"] = visor()

    def goggles():
        img = gear_img(); d = ImageDraw.Draw(img, "RGBA")
        d.ellipse([sc(9), sc(9), sc(14.5), sc(14.5)], outline=TEAL, width=max(3, int(sc(0.45))))
        d.ellipse([sc(17), sc(9), sc(22.5), sc(14.5)], outline=TEAL, width=max(3, int(sc(0.45))))
        d.line([(sc(14.5), sc(11.5)), (sc(17), sc(11.5))], fill=TEAL, width=max(2, int(sc(0.35))))
        return [finalize_gear(img)]
    out["eq_review_goggles"] = goggles()

    def backpack():
        img = gear_img(); d = ImageDraw.Draw(img, "RGBA")
        rounded_rect(d, sc(20), sc(14), sc(26), sc(21), sc(0.8), FA)
        rounded_rect(d, sc(21), sc(15), sc(25), sc(20), sc(0.5), FM)
        ellipse(d, sc(23), sc(17), sc(0.7), sc(0.7), TK)
        return [finalize_gear(img)]
    out["eq_tiny_backpack"] = backpack()

    def scarf():
        img = gear_img(); d = ImageDraw.Draw(img, "RGBA")
        d.arc([sc(9), sc(13), sc(22), sc(22)], 200, 340, fill=TEAL, width=max(5, int(sc(1.3))))
        ellipse(d, sc(10), sc(18), sc(1.4), sc(2.2), TEAL)
        ellipse(d, sc(21), sc(18.5), sc(1.4), sc(2.4), TEAL)
        return [finalize_gear(img)]
    out["eq_soft_scarf"] = scarf()

    def cape(color=PURPLE, name="eq_cape"):
        img = gear_img(); d = ImageDraw.Draw(img, "RGBA")
        d.polygon([(sc(8), sc(14)), (sc(11), sc(14)), (sc(10), sc(23)), (sc(7), sc(22))], fill=color)
        d.polygon([(sc(20), sc(14)), (sc(24), sc(14)), (sc(25), sc(22)), (sc(21), sc(23))], fill=color)
        return [finalize_gear(img)]
    out["eq_cape"] = cape(PURPLE)
    out["eq_diff_cape"] = cape((100, 80, 160, 255), "eq_diff_cape")

    def signal_cloak():
        img = gear_img(); d = ImageDraw.Draw(img, "RGBA")
        d.polygon([(sc(20), sc(11)), (sc(27), sc(12)), (sc(26), sc(23)), (sc(20), sc(22))], fill=BLUE)
        ellipse(d, sc(24), sc(15), sc(0.7), sc(0.7), SP)
        return [finalize_gear(img)]
    out["eq_signal_cloak"] = signal_cloak()

    def fish_rod():
        img = gear_img(); d = ImageDraw.Draw(img, "RGBA")
        d.line([(sc(7), sc(12)), (sc(7), sc(23))], fill=O, width=max(2, int(sc(0.4))))
        d.line([(sc(7), sc(12)), (sc(13), sc(12))], fill=O, width=max(2, int(sc(0.35))))
        ellipse(d, sc(13), sc(13), sc(0.6), sc(0.6), BLUE)
        return [finalize_gear(img)]
    out["eq_fish_rod"] = fish_rod()

    def duck():
        img = gear_img(); d = ImageDraw.Draw(img, "RGBA")
        ellipse(d, sc(8), sc(21.5), sc(2.4), sc(1.8), GOLD)
        ellipse(d, sc(9.5), sc(20), sc(1.4), sc(1.3), GOLD)
        ellipse(d, sc(6.5), sc(21.2), sc(0.7), sc(0.45), PINK)
        ellipse(d, sc(9.5), sc(19.7), sc(0.3), sc(0.3), DARK)
        return [finalize_gear(img)]
    out["eq_rubber_duck"] = duck()

    def keycap():
        img = gear_img(); d = ImageDraw.Draw(img, "RGBA")
        rounded_rect(d, sc(7), sc(19), sc(12), sc(23), sc(0.5), PURPLE)
        ellipse(d, sc(9.5), sc(20.8), sc(0.7), sc(0.5), CREAM)
        return [finalize_gear(img)]
    out["eq_keycap_charm"] = keycap()

    def mini_kb():
        img = gear_img(); d = ImageDraw.Draw(img, "RGBA")
        rounded_rect(d, sc(6), sc(19), sc(15), sc(23), sc(0.5), DARK)
        for x, c in [(8, TEAL), (10.5, CREAM), (13, BLUE)]:
            ellipse(d, sc(x), sc(20.8), sc(0.45), sc(0.35), c)
        return [finalize_gear(img)]
    out["eq_mini_keyboard"] = mini_kb()

    def lantern():
        img = gear_img(); d = ImageDraw.Draw(img, "RGBA")
        rounded_rect(d, sc(6), sc(18), sc(11), sc(24), sc(0.5), DARK)
        ellipse(d, sc(8.5), sc(20.5), sc(1.3), sc(1.6), GOLD)
        ellipse(d, sc(8.5), sc(20.2), sc(0.5), sc(0.5), SP)
        return [finalize_gear(img)]
    out["eq_night_lantern"] = lantern()

    def quill():
        img = gear_img(); d = ImageDraw.Draw(img, "RGBA")
        d.line([(sc(8), sc(12)), (sc(8), sc(23))], fill=O, width=max(2, int(sc(0.4))))
        d.polygon([(sc(8), sc(12)), (sc(10), sc(14)), (sc(8), sc(15))], fill=BLUE)
        return [finalize_gear(img)]
    out["eq_annotation_quill"] = quill()

    def tablet():
        img = gear_img(); d = ImageDraw.Draw(img, "RGBA")
        rounded_rect(d, sc(7), sc(18), sc(14), sc(24), sc(0.5), DARK)
        rounded_rect(d, sc(8), sc(19), sc(13), sc(23), sc(0.3), TEAL)
        return [finalize_gear(img)]
    out["eq_tablet_slate"] = tablet()

    def spark_frames(n=2):
        frames = []
        for phase in range(n):
            img = gear_img(); d = ImageDraw.Draw(img, "RGBA")
            pts = [(6, 12), (25, 13), (15, 4), (8, 22), (24, 20)] if phase == 0 else [
                (7, 14), (24, 11), (16, 5), (9, 21), (23, 19)
            ]
            for x, y in pts:
                ellipse(d, sc(x), sc(y), sc(0.8), sc(0.8), SP)
            frames.append(finalize_gear(img))
        return frames
    out["eq_soft_glow"] = spark_frames(2)
    out["eq_spark_aura"] = spark_frames(2)

    def focus_ring():
        img = gear_img(); d = ImageDraw.Draw(img, "RGBA")
        d.ellipse([sc(9), sc(8), sc(22), sc(22)], outline=BLUE, width=max(3, int(sc(0.4))))
        return [finalize_gear(img)]
    out["eq_focus_ring"] = focus_ring()

    def compile_aura():
        frames = []
        pts = [(5, 14), (26, 14), (10, 5), (21, 5), (16, 24)]
        for phase in range(4):
            img = gear_img(); d = ImageDraw.Draw(img, "RGBA")
            for idx, (x, y) in enumerate(pts):
                if idx % 4 == phase:
                    ellipse(d, sc(x), sc(y), sc(0.9), sc(0.9), PURPLE)
                    ellipse(d, sc(x)+sc(0.3), sc(y)-sc(0.2), sc(0.35), sc(0.35), TH)
            frames.append(finalize_gear(img))
        return frames
    out["eq_compile_aura"] = compile_aura()

    def golden():
        img = gear_img(); d = ImageDraw.Draw(img, "RGBA")
        ellipse(d, sc(15.5), sc(15.5), sc(2.2), sc(2.0), GOLD)
        ellipse(d, sc(15), sc(14.8), sc(0.7), sc(0.6), WH)
        return [finalize_gear(img)]
    out["eq_golden_token"] = golden()

    def origin():
        img = gear_img(); d = ImageDraw.Draw(img, "RGBA")
        rounded_rect(d, sc(13), sc(13), sc(19), sc(18), sc(0.6), GOLD)
        ellipse(d, sc(15.5), sc(15.2), sc(0.9), sc(0.7), WH)
        ellipse(d, sc(12), sc(18), sc(0.6), sc(0.6), SP)
        ellipse(d, sc(19.5), sc(18), sc(0.6), sc(0.6), SP)
        return [finalize_gear(img)]
    out["eq_origin_seal"] = origin()

    return out


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    GEAR_OUT.mkdir(parents=True, exist_ok=True)

    # Clear old tiny pixel PNGs in root (keep gear handled below)
    for p in OUT.glob("*.png"):
        p.unlink()

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
        print(f"base  {name} x{len(frames)}")

    save(OUT / "scene_desk.png", make_scene_desk(0))
    save(OUT / "scene_desk_0.png", make_scene_desk(0))
    save(OUT / "scene_desk_1.png", make_scene_desk(1))
    save(OUT / "scene_bowl.png", make_scene_bowl())
    print("scene desk/bowl")

    for old in GEAR_OUT.glob("*.png"):
        old.unlink()
    gear = make_gears()
    gear_manifest = {}
    for item_id, frames in sorted(gear.items()):
        gear_manifest[item_id] = {"frames": len(frames)}
        if len(frames) == 1:
            save(GEAR_OUT / f"{item_id}.png", frames[0])
        else:
            for i, fr in enumerate(frames):
                save(GEAR_OUT / f"{item_id}_{i}.png", fr)
            save(GEAR_OUT / f"{item_id}.png", frames[0])
        print(f"gear  {item_id} x{len(frames)}")

    # Anchors in final 128 space (CG bottom-left). Old 32-space * 4.
    def a4(x, y):
        return [x * 4, y * 4]

    anchors = {
        "sit": {"head": a4(15, 24), "face": a4(15, 19), "back": a4(22, 14), "held": a4(8, 10), "aura": a4(15, 15), "compact": False},
        "desk": {"head": a4(23, 20), "face": a4(23, 17), "back": a4(28, 15), "held": a4(15, 12), "aura": a4(20, 15), "compact": True},
        "loaf": {"head": a4(12, 12), "face": a4(12, 11), "back": a4(24, 10), "held": a4(9, 8), "aura": a4(16, 10), "compact": True},
        "side": {"head": a4(7, 11), "face": a4(7, 10), "back": a4(24, 10), "held": a4(10, 8), "aura": a4(16, 10), "compact": True},
        "flop": {"head": a4(9, 11), "face": a4(9, 10), "back": a4(24, 8), "held": a4(6, 7), "aura": a4(16, 9), "compact": True},
        "walk": {"head": a4(15, 23), "face": a4(15, 19), "back": a4(22, 15), "held": a4(10, 12), "aura": a4(15, 15), "compact": False},
        "stretch": {"head": a4(10, 15), "face": a4(10, 13), "back": a4(25, 12), "held": a4(8, 9), "aura": a4(16, 12), "compact": True},
        "crouch": {"head": a4(16, 21), "face": a4(16, 18), "back": a4(23, 13), "held": a4(10, 14), "aura": a4(16, 15), "compact": False},
    }

    manifest = {
        "name": "Tokcat HD",
        "version": 9,
        "frameSize": SIZE,
        "displayScale": 1,
        "style": "hd_illustration",
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
        "notes": "v9 HD illustration (128×128, anti-aliased). Not pixel art.",
    }
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"done → {OUT} (HD {SIZE}×{SIZE})")


if __name__ == "__main__":
    main()
