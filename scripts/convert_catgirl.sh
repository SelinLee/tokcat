#!/usr/bin/env bash
# Convert a VRM/glTF catgirl into Tokcat's bundled USDZ slot.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DEFAULT="$ROOT/App/Resources/Models/Catgirl/Catgirl.usdz"
SCRIPT="$ROOT/scripts/blender/vrm_to_usdz.py"

INPUT="${1:-}"
OUTPUT="${2:-$OUT_DEFAULT}"

if [[ -z "$INPUT" ]]; then
  cat <<USAGE
用法:
  scripts/convert_catgirl.sh /path/to/model.vrm [输出.usdz]

默认输出:
  $OUT_DEFAULT

示例:
  # 1) 先把 CC0 底座下到本地
  curl -L -o /tmp/skinnie.vrm \\
    https://github.com/MJMoonbow/VRMavatars/raw/main/skinnie1_5.vrm

  # 2) 转换
  scripts/convert_catgirl.sh /tmp/skinnie.vrm

注意:
  - 需要已安装 Blender.app
  - 输入为 .vrm 时，需在 Blender 中启用 VRM Add-on for Blender
USAGE
  exit 1
fi

if [[ ! -f "$INPUT" ]]; then
  echo "输入文件不存在: $INPUT" >&2
  exit 1
fi

find_blender() {
  local candidates=(
    "$HOME/Library/Application Support/Steam/steamapps/common/Blender/Blender.app/Contents/MacOS/Blender"
    "/Applications/Blender.app/Contents/MacOS/Blender"
    "$HOME/Applications/Blender.app/Contents/MacOS/Blender"
    "/Applications/Blender 4.2.app/Contents/MacOS/Blender"
    "/Applications/Blender 4.3.app/Contents/MacOS/Blender"
    "/Applications/Blender 4.4.app/Contents/MacOS/Blender"
    "/Applications/Blender 4.5.app/Contents/MacOS/Blender"
    "/Applications/Blender 3.6.app/Contents/MacOS/Blender"
  )
  local c
  for c in "${candidates[@]}"; do
    if [[ -x "$c" ]]; then
      echo "$c"
      return 0
    fi
  done
  # Spotlight
  local hit
  hit="$(mdfind 'kMDItemCFBundleIdentifier == "org.blenderfoundation.blender"' 2>/dev/null | head -1 || true)"
  if [[ -n "$hit" && -x "$hit/Contents/MacOS/Blender" ]]; then
    echo "$hit/Contents/MacOS/Blender"
    return 0
  fi
  if command -v blender >/dev/null 2>&1; then
    command -v blender
    return 0
  fi
  return 1
}

if ! BLENDER_BIN="$(find_blender)"; then
  cat <<EOF >&2
未找到 Blender。

请先完成安装：
  1. 打开下载的 Blender .dmg
  2. 把 Blender.app 拖到 /Applications
  3. 首次打开一次（过 Gatekeeper）

若已安装但不在 /Applications，可手动指定：
  BLENDER=/path/to/Blender.app/Contents/MacOS/Blender scripts/convert_catgirl.sh model.vrm
EOF
  exit 1
fi

if [[ -n "${BLENDER:-}" ]]; then
  BLENDER_BIN="$BLENDER"
fi

echo "Blender: $BLENDER_BIN"
echo "Input : $INPUT"
echo "Output: $OUTPUT"

"$BLENDER_BIN" -b -P "$SCRIPT" -- --input "$INPUT" --output "$OUTPUT" --target-height 1.7

echo
echo "完成。接下来："
echo "  cd $ROOT && swift run TokcatApp"
echo "  设置 → 宠物 → 皮肤选择「猫娘」"
echo
echo "若角色是普通二次元女孩（无猫耳），可在 Blender GUI 里加耳/尾后再导出，或使用 VRoid 自制猫娘。"
