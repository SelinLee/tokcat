#!/usr/bin/env python3
"""Install all V3 frames, build contact sheets, write report."""
from __future__ import annotations
import json, subprocess, sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import numpy as np

ROOT = Path('/Users/lishihao/Claude/tokencat')
PROD = ROOT / 'docs/assets/ai_gen_test/m1_v3_full'
RAW = PROD / 'raw'
F128 = PROD / 'frames128'
APP = ROOT / 'App/Resources/Sprites/TokcatPixel'
INSTALL = Path('/tmp/tokcat_v3full/install_one.py')

CLIPS = {
    'idle': 4, 'happy': 3, 'sad': 3, 'wave': 4, 'interact': 3, 'jump': 5, 'level_up': 5,
    'working': 4, 'review': 6, 'waiting': 4, 'failed': 4, 'sleepy': 3, 'rest': 4,
    'hungry': 3, 'eating': 4, 'pace': 8, 'groom': 4, 'look_around': 6,
}
EXTRA = [
    'scene_desk', 'scene_desk_0', 'scene_desk_1', 'scene_bowl',
    'eq_beanie', 'eq_soft_scarf', 'eq_rubber_duck', 'eq_headphones',
    'eq_monocle', 'eq_cape', 'eq_spark_aura', 'skin_mint', 'skin_midnight',
]


def need_list():
    need = []
    for c, n in CLIPS.items():
        for i in range(n):
            need.append(f'{c}_{i}')
    return need + EXTRA


def install_all():
    names = sorted(p.stem for p in RAW.glob('*.png') if p.stat().st_size > 20000)
    ok = 0
    for n in names:
        r = subprocess.run([sys.executable, str(INSTALL), n], capture_output=True, text=True)
        if r.returncode == 0:
            ok += 1
        else:
            print('install fail', n, r.stdout, r.stderr)
    print('installed', ok, '/', len(names))


def contact_sheet(names, out: Path, cols=8, cell=96, title=''):
    rows = (len(names) + cols - 1) // cols
    sheet = Image.new('RGBA', (cols * cell, rows * cell + 28), (250, 250, 250, 255))
    draw = ImageDraw.Draw(sheet)
    draw.text((8, 6), title or out.stem, fill=(20, 20, 20, 255))
    for i, name in enumerate(names):
        p = F128 / f'{name}.png'
        if not p.exists():
            p = APP / f'{name}.png'
            if name.startswith('eq_'):
                p = APP / 'gear' / f'{name}.png'
        r, c = divmod(i, cols)
        x, y = c * cell, 28 + r * cell
        if p.exists():
            im = Image.open(p).convert('RGBA').resize((cell - 8, cell - 8), Image.Resampling.LANCZOS)
            bg = Image.new('RGBA', (cell - 8, cell - 8), (255, 255, 255, 255))
            bg.alpha_composite(im)
            sheet.paste(bg, (x + 4, y + 4))
        draw.text((x + 4, y + cell - 14), name[:14], fill=(40, 40, 40, 255))
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out)
    print('sheet', out)


def main():
    need = need_list()
    have = [n for n in need if (RAW / f'{n}.png').exists() and (RAW / f'{n}.png').stat().st_size > 20000]
    missing = [n for n in need if n not in have]
    print('have', len(have), 'missing', len(missing), missing)
    if missing:
        return 1
    install_all()
    # sheets by family
    for clip, n in CLIPS.items():
        names = [f'{clip}_{i}' for i in range(n)]
        contact_sheet(names, PROD / 'sheets' / f'{clip}.png', cols=min(8, n), title=clip)
    contact_sheet([e for e in EXTRA if e.startswith('eq_')], PROD / 'sheets' / 'gear.png', cols=4, title='gear')
    contact_sheet([e for e in EXTRA if e.startswith('scene_')], PROD / 'sheets' / 'scenes.png', cols=4, title='scenes')
    contact_sheet([e for e in EXTRA if e.startswith('skin_')], PROD / 'sheets' / 'skins.png', cols=2, title='skins')
    # big overview first frame of each clip
    overview = [f'{c}_0' for c in CLIPS] + EXTRA
    contact_sheet(overview, PROD / 'sheets' / 'overview.png', cols=8, title='V3 full overview')
    report = {
        'version': 'V3',
        'count': len(have),
        'clips': CLIPS,
        'extra': EXTRA,
        'raw_dir': str(RAW),
        'frames128': str(F128),
        'app': str(APP),
    }
    (PROD / 'PRODUCTION_REPORT.json').write_text(json.dumps(report, indent=2))
    print('FINAL OK', len(have))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
