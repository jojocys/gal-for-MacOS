#!/bin/zsh
set -euo pipefail

# P3: 将 Swift Package 构建产物包装为可双击运行的 .app（开发者侧脚本）
# 用法：
#   ./scripts/build_release_app.sh

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build"
DIST_DIR="$ROOT_DIR/dist"
ASSETS_DIR="$ROOT_DIR/assets"
APP_NAME="GAL FOR MacOS"
EXECUTABLE_NAME="VNLauncherZero"
APP_BUNDLE="$DIST_DIR/${APP_NAME}.app"
MACOS_DIR="$APP_BUNDLE/Contents/MacOS"
RES_DIR="$APP_BUNDLE/Contents/Resources"
PLIST_FILE="$APP_BUNDLE/Contents/Info.plist"
BIN_PATH="$BUILD_DIR/release/$EXECUTABLE_NAME"
ICON_FILE="$ASSETS_DIR/VNLauncherZero.icns"

mkdir -p "$DIST_DIR"

echo "[0/4] Ensuring app icon..."
if [[ ! -f "$ICON_FILE" ]]; then
  if [[ -x "$ROOT_DIR/scripts/generate_app_icon.sh" ]]; then
    "$ROOT_DIR/scripts/generate_app_icon.sh" || true
  elif [[ -f "$ROOT_DIR/scripts/generate_app_icon.sh" ]]; then
    zsh "$ROOT_DIR/scripts/generate_app_icon.sh" || true
  fi
fi

echo "[1/4] Building release binary..."
swift build -c release --package-path "$ROOT_DIR"

if [[ ! -x "$BIN_PATH" ]]; then
  echo "Release binary not found: $BIN_PATH"
  exit 1
fi

echo "[2/4] Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RES_DIR"
cp "$BIN_PATH" "$MACOS_DIR/$EXECUTABLE_NAME"
chmod +x "$MACOS_DIR/$EXECUTABLE_NAME"
if [[ -f "$ICON_FILE" ]]; then
  cp "$ICON_FILE" "$RES_DIR/GAL FOR MacOS.icns"
fi

echo "[3/4] Writing Info.plist..."
cat > "$PLIST_FILE" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleExecutable</key>
  <string>${EXECUTABLE_NAME}</string>
  <key>CFBundleIconFile</key>
  <string>GAL FOR MacOS.icns</string>
  <key>CFBundleIdentifier</key>
  <string>local.vnlauncher.zero</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
EOF

echo "[4/4] Ad-hoc signing (optional)..."
if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null 2>&1 || true
fi

echo
echo "Done:"
echo "  $APP_BUNDLE"
echo
echo "Tip:"
echo "  First launch may still trigger Gatekeeper warnings for Wine (not for this wrapper app)."
if [[ -f "$ICON_FILE" ]]; then
  echo "  App icon: embedded (${ICON_FILE})"
else
  echo "  App icon: not found, bundle was built without custom icon."
fi
