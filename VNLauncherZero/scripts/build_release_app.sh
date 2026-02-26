#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="GAL FOR MacOS"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_ZIP="$DIST_DIR/$APP_NAME.app.zip"
APP_ZIP_SHA="$APP_ZIP.sha256.txt"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
EMBEDDED_WINE_DIR="$RESOURCES_DIR/EmbeddedWine"
INSTALLERS_DIR="$RESOURCES_DIR/Installers"
EXECUTABLE_NAME="$APP_NAME"
PACKAGE_BIN="$ROOT_DIR/.build/release/VNLauncherZero"
ICON_SOURCE="$ROOT_DIR/assets/VNLauncherZero.icns"
ICON_NAME="$APP_NAME.icns"
WINE_SOURCE_APP="${EMBED_WINE_APP_PATH:-}"
XQUARTZ_SOURCE_PKG="${EMBED_XQUARTZ_PKG_PATH:-}"

mkdir -p "$DIST_DIR"

if [[ -z "$WINE_SOURCE_APP" ]]; then
  for candidate in \
    "/Applications/Wine Stable.app" \
    "/Applications/Wine.app" \
    "$HOME/Applications/Wine Stable.app" \
    "$HOME/Applications/Wine.app"
  do
    if [[ -d "$candidate" ]]; then
      WINE_SOURCE_APP="$candidate"
      break
    fi
  done
fi

if [[ -z "$WINE_SOURCE_APP" || ! -d "$WINE_SOURCE_APP" ]]; then
  echo "Embedded Wine source app not found." >&2
  echo "Please install Wine first, or set EMBED_WINE_APP_PATH to your Wine.app path." >&2
  exit 1
fi

if [[ -z "$XQUARTZ_SOURCE_PKG" ]]; then
  for candidate in \
    "$HOME/Downloads/XQuartz.pkg" \
    "$HOME/Downloads/XQuartz-2.8.5.pkg" \
    "$HOME/Desktop/XQuartz-2.8.5.pkg" \
    "$HOME/Desktop/XQuartz.pkg" \
    "/Users/gaoxiaoli/Desktop/XQuartz-2.8.5.pkg"
  do
    if [[ -f "$candidate" ]]; then
      XQUARTZ_SOURCE_PKG="$candidate"
      break
    fi
  done
fi

if [[ -z "$XQUARTZ_SOURCE_PKG" ]]; then
  for candidate in /Volumes/*XQuartz*/*.pkg(N) /Volumes/*xquartz*/*.pkg(N); do
    if [[ -f "$candidate" ]]; then
      XQUARTZ_SOURCE_PKG="$candidate"
      break
    fi
  done
fi

if [[ -z "$XQUARTZ_SOURCE_PKG" || ! -f "$XQUARTZ_SOURCE_PKG" ]]; then
  echo "Embedded XQuartz package not found." >&2
  echo "Please put XQuartz .pkg in Downloads/Desktop, keep the XQuartz DMG mounted, or set EMBED_XQUARTZ_PKG_PATH to the pkg path." >&2
  exit 1
fi

echo "[0/7] Ensuring app icon..."
"$ROOT_DIR/scripts/generate_app_icon.sh"

echo "[1/7] Cleaning local build cache to avoid path mismatch..."
rm -rf "$ROOT_DIR/.build"

echo "[2/7] Building release binary..."
(cd "$ROOT_DIR" && swift build -c release)

if [[ ! -x "$PACKAGE_BIN" ]]; then
  echo "Release binary not found: $PACKAGE_BIN" >&2
  exit 1
fi

echo "[3/7] Assembling .app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$EMBEDDED_WINE_DIR" "$INSTALLERS_DIR"
cp "$PACKAGE_BIN" "$MACOS_DIR/$EXECUTABLE_NAME"
chmod +x "$MACOS_DIR/$EXECUTABLE_NAME"
cp "$ICON_SOURCE" "$RESOURCES_DIR/$ICON_NAME"

echo "[4/7] Embedding Wine runtime..."
WINE_APP_NAME="$(basename "$WINE_SOURCE_APP")"
ditto "$WINE_SOURCE_APP" "$EMBEDDED_WINE_DIR/$WINE_APP_NAME"
if command -v xattr >/dev/null 2>&1; then
  xattr -dr com.apple.quarantine "$EMBEDDED_WINE_DIR/$WINE_APP_NAME" >/dev/null 2>&1 || true
fi

echo "[4.5/7] Embedding XQuartz installer..."
cp "$XQUARTZ_SOURCE_PKG" "$INSTALLERS_DIR/XQuartz.pkg"
if command -v xattr >/dev/null 2>&1; then
  xattr -dr com.apple.quarantine "$INSTALLERS_DIR/XQuartz.pkg" >/dev/null 2>&1 || true
fi

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

echo "[5/7] Ad-hoc signing .app bundle..."
codesign --force --deep --sign - --timestamp=none "$EMBEDDED_WINE_DIR/$WINE_APP_NAME" || true
codesign --force --deep --sign - --timestamp=none "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=1 "$APP_BUNDLE" >/dev/null

echo "[6/7] Creating app zip + sha256..."
rm -f "$APP_ZIP" "$APP_ZIP_SHA"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$APP_ZIP"
shasum -a 256 "$APP_ZIP" > "$APP_ZIP_SHA"

echo "[7/7] Done"
echo "App bundle: $APP_BUNDLE"
echo "Embedded Wine: $EMBEDDED_WINE_DIR/$WINE_APP_NAME"
echo "Embedded XQuartz installer: $INSTALLERS_DIR/XQuartz.pkg"
echo "App zip: $APP_ZIP"
echo "App zip sha256: $APP_ZIP_SHA"
