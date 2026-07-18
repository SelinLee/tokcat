#!/bin/bash
set -e
name="$1"; prompt="$2"
export BOTCF_API_KEY="${BOTCF_API_KEY:-}"
MASTER="/Users/lishihao/Claude/tokencat/docs/assets/ai_gen_test/m1_v3_full/master/V3_master.png"
RAW="/Users/lishihao/Claude/tokencat/docs/assets/ai_gen_test/m1_v3_full/raw"
PREFIX='Use this exact Tokcat V3 identity as the ONLY character design reference. Solid pure BLACK body/face/muzzle/mouth/nose. Pure WHITE inner ears only. Luna-like large cute WHITE eye whites with BLACK pupils. NO white muzzle patch. NO cyan/blue, NO moon, NO crescent, NO stars. Manga/chibi Q-version LINE-ART face, pure flat colors, thick clean outlines, VERY LARGE upright ears. Pure white background, full body centered. NO photoreal, NO fur texture, NO gradients, NO text.'
out="$RAW/${name}.png"
if [ -f "$out" ] && [ "$(wc -c < "$out")" -gt 20000 ]; then
  echo "skip $name"
  # still ensure install
  /Users/lishihao/miniforge3/bin/python3 /tmp/tokcat_v3full/install_one.py "$name" || true
  exit 0
fi
echo "=== $name ==="
curl -sS --max-time 180 "https://botcf.com/v1/images/edits" \
  -H "Authorization: Bearer $BOTCF_API_KEY" \
  -F "model=gpt-image-2" -F "size=1024x1024" \
  -F "image=@${MASTER};type=image/png" \
  -F "prompt=${PREFIX} ${prompt}" \
  -o "/tmp/tokcat_v3full/${name}.json"
/Users/lishihao/miniforge3/bin/python3 /tmp/tokcat_v3full/install_one.py "$name"
