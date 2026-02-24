#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="GAL FOR MacOS"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
EXECUTABLE_NAME="$APP_NAME"
PACKAGE_BIN="$ROOT_DIR/.build/release/VNLauncherZero"
ICON_SOURCE="$ROOT_DIR/assets/VNLauncherZero.icns"
ICON_NAME="$APP_NAME.icns"

mkdir -p "$DIST_DIR"

echo "[0/4] Ensuring app icon..."
"$ROOT_DIR/scripts/generate_app_icon.sh"

echo "[1/4] Cleaning local build cache to avoid path mismatch..."
rm -rf "$ROOT_DIR/.build"

echo "[2/4] Building release binary..."
(cd "$ROOT_DIR" && swift build -c release)

if [[ ! -x "$PACKAGE_BIN" ]]; then
  echo "Release binary not found: $PACKAGE_BIN" >&2
  exit 1
fi

echo "[3/4] Assembling .app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$PACKAGE_BIN" "$MACOS_DIR/$EXECUTABLE_NAME"
chmod +x "$MACOS_DIR/$EXECUTABLE_NAME"
cp "$ICON_SOURCE" "$RESOURCES_DIR/$ICON_NAME"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$EXECUTABLE_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>local.gaoxiaoli.galformacos</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.0</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.games</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>CFBundleIconFile</key>
  <string>$ICON_NAME</string>
</dict>
</plist>
PLIST

echo "[4/4] Done"
echo "App bundle: $APP_BUNDLE"
