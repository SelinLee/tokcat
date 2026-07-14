#!/usr/bin/env bash
# Convert a VRM/glTF model into Tokcat's bundled pink-cat USDZ slot.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DEFAULT="$ROOT/App/Resources/Models/Catgirl/Catgirl.usdz"
SCRIPT="$ROOT/scripts/blender/vrm_to_usdz.py"

INPUT="${1:-}"
OUTPUT="${2:-$OUT_DEFAULT}"

if [[ -z "$INPUT" ]]; then
  cat <<USAGE
用法:
  scripts/convert_pet_model.sh /path/to/model.vrm [输出.usdz]

默认输出:
  $OUT_DEFAULT

示例:
  scripts/convert_pet_model.sh /tmp/ChubbyTubbyCat.vrm
USAGE
  exit 1
fi

if [[ -n "${BLENDER:-}" ]]; then
  BLENDER_BIN="$BLENDER"
elif command -v blender >/dev/null 2>&1; then
  BLENDER_BIN="$(command -v blender)"
elif [[ -x "/Applications/Blender.app/Contents/MacOS/Blender" ]]; then
  BLENDER_BIN="/Applications/Blender.app/Contents/MacOS/Blender"
else
  echo "找不到 Blender。请安装或设置 BLENDER=/path/to/Blender" >&2
  exit 1
fi

echo "Blender: $BLENDER_BIN"
echo "Input : $INPUT"
echo "Output: $OUTPUT"

"$BLENDER_BIN" -b -P "$SCRIPT" -- --input "$INPUT" --output "$OUTPUT" --target-height 1.7

echo
echo "完成。接下来："
echo "  cd $ROOT && swift run TokcatApp"
echo "  设置 → 宠物 → 皮肤选择「粉猫」"
