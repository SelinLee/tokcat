#!/usr/bin/env bash
# Build a distributable Tokcat.app (ad-hoc signed) + zip + DMG.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="Tokcat"
EXEC_NAME="TokcatApp"
BUNDLE_ID="com.selinlee.tokcat"
MIN_SYSTEM="13.0"
VERSION="${TOKCAT_VERSION:-0.3.1}"
BUILD_NUMBER="${TOKCAT_BUILD:-1}"

DIST_DIR="$ROOT/dist"
APP_DIR="$DIST_DIR/${APP_NAME}.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"
ZIP_PATH="$DIST_DIR/${APP_NAME}-${VERSION}-macos.zip"
DMG_PATH="$DIST_DIR/${APP_NAME}-${VERSION}-macos.dmg"

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

# Executable
cp "$BIN" "$MACOS_DIR/${EXEC_NAME}"
chmod +x "$MACOS_DIR/${EXEC_NAME}"

# SwiftPM resource bundle: put under Contents/Resources and also next to the
# executable (Bundle.module for executable targets resolves relative to the binary).
# Make the MacOS copy a proper bundle with Info.plist so codesign accepts --deep.
copy_resource_bundle() {
  local dest="$1"
  rm -rf "$dest"
  mkdir -p "$dest"
  # Copy payload files
  rsync -a --delete "$RES_BUNDLE_SRC"/ "$dest"/
  # Ensure bundle Info.plist exists (SwiftPM loose bundles often lack it).
  if [[ ! -f "$dest/Info.plist" ]]; then
    cat > "$dest/Info.plist" <<'BUNDLEPLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>com.selinlee.tokcat.resources</string>
  <key>CFBundleName</key>
  <string>Tokcat_TokcatApp</string>
  <key>CFBundlePackageType</key>
  <string>BNDL</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
</dict>
</plist>
BUNDLEPLIST
  fi
}

copy_resource_bundle "$MACOS_DIR/Tokcat_TokcatApp.bundle"
copy_resource_bundle "$RESOURCES_DIR/Tokcat_TokcatApp.bundle"

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
# Sign nested resource bundles first, then the app.
codesign --force --sign - "$MACOS_DIR/Tokcat_TokcatApp.bundle" || true
codesign --force --sign - "$RESOURCES_DIR/Tokcat_TokcatApp.bundle" || true
codesign --force --sign - "$MACOS_DIR/${EXEC_NAME}"
codesign --force --deep --options runtime --sign - "$APP_DIR" || codesign --force --deep --sign - "$APP_DIR"

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

echo "==> DMG for distribution"
DMG_PATH="$DIST_DIR/${APP_NAME}-${VERSION}-macos.dmg"
DMG_STAGE="$DIST_DIR/dmg-stage"
rm -rf "$DMG_STAGE" "$DMG_PATH"
mkdir -p "$DMG_STAGE"
# Keep Parent-style layout: app + Applications shortcut for drag-install.
ditto "$APP_DIR" "$DMG_STAGE/${APP_NAME}.app"
ln -s /Applications "$DMG_STAGE/Applications"
# Temporary RW image → compress to UDZO
TMP_DMG="$DIST_DIR/.${APP_NAME}-${VERSION}-rw.dmg"
rm -f "$TMP_DMG"
hdiutil create \
  -volname "$APP_NAME $VERSION" \
  -srcfolder "$DMG_STAGE" \
  -ov \
  -fs HFS+ \
  -format UDRW \
  "$TMP_DMG" >/dev/null
hdiutil convert "$TMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH" >/dev/null
rm -f "$TMP_DMG"
rm -rf "$DMG_STAGE"

# SHA256 (zip + dmg)
SHA_PATH="$DIST_DIR/${APP_NAME}-${VERSION}-macos.sha256"
if command -v shasum >/dev/null 2>&1; then
  {
    shasum -a 256 "$ZIP_PATH"
    shasum -a 256 "$DMG_PATH"
  } | tee "$SHA_PATH"
elif command -v sha256sum >/dev/null 2>&1; then
  {
    sha256sum "$ZIP_PATH"
    sha256sum "$DMG_PATH"
  } | tee "$SHA_PATH"
fi

cat > "$DIST_DIR/INSTALL.txt" <<TXT
Tokcat ${VERSION} — macOS 菜单栏用量监控 + 像素宠物

推荐安装（DMG）：
1. 打开 Tokcat-${VERSION}-macos.dmg
2. 将 Tokcat.app 拖到 Applications
3. 首次启动：右键 Tokcat.app → 打开（ad-hoc 签名，需绕过 Gatekeeper 一次）
4. 菜单栏出现猫头图标

备选（Zip）：
1. 解压 Tokcat-${VERSION}-macos.zip 得到 Tokcat.app
2. 拖到 /Applications（或任意位置）
3. 同样：右键 → 打开

说明：
- 当前为 ad-hoc 签名，未做 Apple Developer ID 公证
- macOS 13+，架构以本机构建为准（通常 Apple Silicon）
- 数据仅存本地：~/Library/Application Support/TokenCat/
- 应用本身不联网、不上传

卸载：
- 删除 Tokcat.app
- 可选删除 ~/Library/Application Support/TokenCat/
TXT

echo
echo "Done:"
echo "  App : $APP_DIR"
echo "  Zip : $ZIP_PATH"
echo "  DMG : $DMG_PATH"
du -sh "$APP_DIR" "$ZIP_PATH" "$DMG_PATH"
