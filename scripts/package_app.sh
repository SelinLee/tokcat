#!/usr/bin/env bash
# Build a distributable Tokcat.app (ad-hoc signed) + zip.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="Tokcat"
EXEC_NAME="TokcatApp"
BUNDLE_ID="com.selinlee.tokcat"
MIN_SYSTEM="13.0"
VERSION="${TOKCAT_VERSION:-0.2.0}"
BUILD_NUMBER="${TOKCAT_BUILD:-1}"

DIST_DIR="$ROOT/dist"
APP_DIR="$DIST_DIR/${APP_NAME}.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"
ZIP_PATH="$DIST_DIR/${APP_NAME}-${VERSION}-macos.zip"

echo "==> Building release binary"
swift build -c release --product TokcatApp

TRIPLE="$(swift -print-target-info 2>/dev/null | python3 -c 'import sys,json; print(json.load(sys.stdin)["target"]["triple"])' 2>/dev/null || true)"
if [[ -z "${TRIPLE:-}" ]]; then
  ARCH="$(uname -m)"
  case "$ARCH" in
    arm64) TRIPLE="arm64-apple-macosx" ;;
    x86_64) TRIPLE="x86_64-apple-macosx" ;;
    *) TRIPLE="arm64-apple-macosx" ;;
  esac
fi

BIN="$ROOT/.build/release/${EXEC_NAME}"
if [[ ! -x "$BIN" ]]; then
  # Fallback for triple-scoped build dirs used by some toolchains.
  CANDIDATE="$(find "$ROOT/.build" -type f -path "*/release/${EXEC_NAME}" -perm -111 2>/dev/null | head -1 || true)"
  if [[ -n "$CANDIDATE" ]]; then
    BIN="$CANDIDATE"
  fi
fi
if [[ ! -x "$BIN" ]]; then
  echo "Release binary not found under .build/**/release/${EXEC_NAME}" >&2
  exit 1
fi

# SwiftPM resource bundle next to the executable.
RES_BUNDLE_SRC="$(dirname "$BIN")/Tokcat_TokcatApp.bundle"
if [[ ! -d "$RES_BUNDLE_SRC" ]]; then
  RES_BUNDLE_SRC="$(find "$ROOT/.build" -type d -name 'Tokcat_TokcatApp.bundle' | head -1 || true)"
fi
if [[ ! -d "$RES_BUNDLE_SRC" ]]; then
  echo "Resource bundle Tokcat_TokcatApp.bundle not found" >&2
  exit 1
fi

echo "==> Assembling ${APP_NAME}.app"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

# Binary + resource bundle must sit together for Bundle.module resolution.
cp "$BIN" "$MACOS_DIR/${EXEC_NAME}"
chmod +x "$MACOS_DIR/${EXEC_NAME}"
rm -rf "$MACOS_DIR/Tokcat_TokcatApp.bundle"
cp -R "$RES_BUNDLE_SRC" "$MACOS_DIR/Tokcat_TokcatApp.bundle"

# Also mirror into Resources for Finder/AppKit conventions.
rm -rf "$RESOURCES_DIR/Tokcat_TokcatApp.bundle"
cp -R "$RES_BUNDLE_SRC" "$RESOURCES_DIR/Tokcat_TokcatApp.bundle"

# PkgInfo
printf 'APPL????' > "$CONTENTS/PkgInfo"

# Info.plist
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh-Hans</string>
  <key>CFBundleExecutable</key>
  <string>${EXEC_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key>
  <string>${APP_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${BUILD_NUMBER}</string>
  <key>LSMinimumSystemVersion</key>
  <string>${MIN_SYSTEM}</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSSupportsAutomaticGraphicsSwitching</key>
  <true/>
  <key>CFBundleIconFile</key>
  <string></string>
</dict>
</plist>
PLIST

echo "==> Ad-hoc codesign"
codesign --force --deep --sign - "$APP_DIR"

echo "==> Verify bundle"
if command -v spctl >/dev/null 2>&1; then
  # Ad-hoc signed apps will not pass Gatekeeper assessment; just structure-check.
  true
fi
codesign -dv --verbose=2 "$APP_DIR" 2>&1 | sed -n '1,20p'
/usr/bin/plutil -lint "$CONTENTS/Info.plist" >/dev/null

# Smoke: ensure executable linkage is arm64/x86_64 macOS
file "$MACOS_DIR/${EXEC_NAME}"

echo "==> Zip for distribution"
rm -f "$ZIP_PATH"
(
  cd "$DIST_DIR"
  ditto -c -k --sequesterRsrc --keepParent "${APP_NAME}.app" "$(basename "$ZIP_PATH")"
)

# SHA256
if command -v shasum >/dev/null 2>&1; then
  shasum -a 256 "$ZIP_PATH" | tee "$DIST_DIR/${APP_NAME}-${VERSION}-macos.sha256"
elif command -v sha256sum >/dev/null 2>&1; then
  sha256sum "$ZIP_PATH" | tee "$DIST_DIR/${APP_NAME}-${VERSION}-macos.sha256"
fi

cat > "$DIST_DIR/INSTALL.txt" <<TXT
Tokcat ${VERSION} — macOS 菜单栏宠物

安装：
1. 解压得到 Tokcat.app
2. 拖到 /Applications（或任意位置）
3. 首次打开：右键 Tokcat.app → 打开（通过 Gatekeeper）
4. 菜单栏出现猫头图标；设置… 可切换皮肤 / 指标

说明：
- 当前为 ad-hoc 签名，未做 Apple Developer ID 公证
- macOS 13+，Apple Silicon / 以本机构建架构为准
- 数据仅存本地：~/Library/Application Support/TokenCat/

卸载：
- 删除 Tokcat.app
- 可选删除 ~/Library/Application Support/TokenCat/
TXT

echo
echo "Done:"
echo "  App : $APP_DIR"
echo "  Zip : $ZIP_PATH"
du -sh "$APP_DIR" "$ZIP_PATH"
