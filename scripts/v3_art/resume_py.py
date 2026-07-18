#!/usr/bin/env python3
"""Sequential resume producer for Tokcat V3 full set."""
from __future__ import annotations
import base64
import json
import os
import subprocess
import sys
import time
import traceback
from pathlib import Path

ROOT = Path('/Users/lishihao/Claude/tokencat')
PROD = ROOT / 'docs/assets/ai_gen_test/m1_v3_full'
RAW = PROD / 'raw'
MASTER = PROD / 'master' / 'V3_master.png'
TMP = Path('/tmp/tokcat_v3full')
LOG = PROD / 'logs' / f'resume_py_{time.strftime("%Y%m%d_%H%M%S")}.log'
JOBS = TMP / 'jobs.txt'
INSTALL = TMP / 'install_one.py'

PREFIX = (
    'Use this exact Tokcat V3 identity as the ONLY character design reference. '
    'Solid pure BLACK body/face/muzzle/mouth/nose. Pure WHITE inner ears only. '
    'Luna-like large cute WHITE eye whites with BLACK pupils. NO white muzzle patch. '
    'NO cyan/blue, NO moon, NO crescent, NO stars. Manga/chibi Q-version LINE-ART face, '
    'pure flat colors, thick clean outlines, VERY LARGE upright ears. Pure white background, '
    'full body centered. NO photoreal, NO fur texture, NO gradients, NO text.'
)

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


def log(msg: str) -> None:
    line = f"[{time.strftime('%H:%M:%S')}] {msg}"
    print(line, flush=True)
    with LOG.open('a') as f:
        f.write(line + '\n')


def load_jobs() -> dict[str, str]:
    jobs = {}
    for line in JOBS.read_text().splitlines():
        if '|' not in line:
            continue
        n, p = line.split('|', 1)
        jobs[n.strip()] = p.strip()
    return jobs


def need_list() -> list[str]:
    need = []
    for c, n in CLIPS.items():
        for i in range(n):
            need.append(f'{c}_{i}')
    need += EXTRA
    return need


def have_raw(name: str) -> bool:
    p = RAW / f'{name}.png'
    return p.exists() and p.stat().st_size > 20000


def get_api_key() -> str:
    k = os.environ.get('BOTCF_API_KEY', '').strip()
    if k:
        return k
    cfg = Path.home() / '.codex/skills/tokcat-ai-art/config/botcf.json'
    if cfg.exists():
        return str(json.loads(cfg.read_text()).get('api_key') or '').strip()
    return ''


def gen_one(name: str, prompt: str, api_key: str) -> bool:
    out = RAW / f'{name}.png'
    if have_raw(name):
        log(f'skip {name}')
        subprocess.run([sys.executable, str(INSTALL), name], check=False)
        return True
    jp = TMP / f'{name}.json'
    full_prompt = f'{PREFIX} {prompt}'
    log(f'DO {name}')
    cmd = [
        'curl', '-sS', '--max-time', '180',
        'https://botcf.com/v1/images/edits',
        '-H', f'Authorization: Bearer {api_key}',
        '-F', 'model=gpt-image-2',
        '-F', 'size=1024x1024',
        '-F', f'image=@{MASTER};type=image/png',
        '-F', f'prompt={full_prompt}',
        '-o', str(jp),
    ]
    r = subprocess.run(cmd)
    if r.returncode != 0:
        log(f'curl fail rc={r.returncode} {name}')
        return False
    try:
        data = json.loads(jp.read_text())
    except Exception as e:
        log(f'json parse fail {name}: {e} head={jp.read_bytes()[:120]!r}')
        return False
    if 'error' in data:
        log(f'api error {name}: {data["error"]}')
        return False
    if not data.get('data'):
        log(f'no data {name}: keys={list(data.keys())}')
        return False
    b64 = data['data'][0].get('b64_json')
    if not b64:
        log(f'no b64 {name}')
        return False
    out.write_bytes(base64.b64decode(b64))
    r2 = subprocess.run([sys.executable, str(INSTALL), name], capture_output=True, text=True)
    log(f'OK {name} size={out.stat().st_size} install={r2.stdout.strip()}')
    return r2.returncode == 0


def main() -> int:
    LOG.parent.mkdir(parents=True, exist_ok=True)
    RAW.mkdir(parents=True, exist_ok=True)
    api_key = get_api_key()
    if not api_key:
        log('missing API key')
        return 2
    jobs = load_jobs()
    need = need_list()
    missing = [n for n in need if not have_raw(n)]
    log(f'start missing={len(missing)} total={len(need)}')
    ok = fail = 0
    for name in missing:
        prompt = jobs.get(name)
        if not prompt:
            log(f'NO_PROMPT {name}')
            fail += 1
            continue
        success = False
        for attempt in range(1, 3):
            try:
                if gen_one(name, prompt, api_key):
                    success = True
                    break
            except Exception:
                log(f'exc {name}: {traceback.format_exc()}')
            log(f'retry {name} attempt={attempt}')
            time.sleep(2)
        if success:
            ok += 1
        else:
            fail += 1
    # final count
    have = [n for n in need if have_raw(n)]
    still = [n for n in need if not have_raw(n)]
    (TMP / 'missing.txt').write_text('\n'.join(still) + ('\n' if still else ''))
    log(f'end ok={ok} fail={fail} have={len(have)} still={len(still)}')
    if still:
        log('still: ' + ','.join(still))
    return 0 if not still else 1


if __name__ == '__main__':
    raise SystemExit(main())
