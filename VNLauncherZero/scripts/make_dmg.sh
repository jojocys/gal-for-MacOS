#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="GAL FOR MacOS"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"
DMG_SHA_PATH="$DMG_PATH.sha256.txt"
STAGE_DIR="$DIST_DIR/.dmg-staging"
EMBEDDED_WINE_DIR="$APP_BUNDLE/Contents/Resources/EmbeddedWine"
EMBEDDED_XQUARTZ_PKG="$APP_BUNDLE/Contents/Resources/Installers/XQuartz.pkg"
EMBEDDED_WINE_BIN=""

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "App bundle not found. Run build_release_app.sh first." >&2
  exit 1
fi

for candidate in \
  "$EMBEDDED_WINE_DIR/Wine Stable.app/Contents/Resources/wine/bin/wine64" \
  "$EMBEDDED_WINE_DIR/Wine Stable.app/Contents/Resources/wine/bin/wine" \
  "$EMBEDDED_WINE_DIR/Wine.app/Contents/Resources/wine/bin/wine64" \
  "$EMBEDDED_WINE_DIR/Wine.app/Contents/Resources/wine/bin/wine"
do
  if [[ -x "$candidate" ]]; then
    EMBEDDED_WINE_BIN="$candidate"
    break
  fi
done

if [[ -z "$EMBEDDED_WINE_BIN" ]]; then
  echo "Embedded Wine runtime not found in app bundle." >&2
  echo "Please run ./scripts/build_release_app.sh first (it now embeds Wine into the app)." >&2
  exit 1
fi

if [[ ! -f "$EMBEDDED_XQUARTZ_PKG" ]]; then
  echo "Embedded XQuartz installer not found in app bundle." >&2
  echo "Please run ./scripts/build_release_app.sh after placing XQuartz .pkg on Desktop." >&2
  exit 1
fi

rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"

echo "[1/5] Verifying embedded Wine..."
echo "Embedded Wine binary: $EMBEDDED_WINE_BIN"
echo "Embedded XQuartz pkg: $EMBEDDED_XQUARTZ_PKG"

echo "[2/5] Ad-hoc signing app bundle..."
codesign --force --deep --sign - --timestamp=none "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=1 "$APP_BUNDLE" >/dev/null

echo "[3/5] Preparing staging folder..."
cp -R "$APP_BUNDLE" "$STAGE_DIR/"
ln -s /Applications "$STAGE_DIR/Applications"
rm -f "$DMG_PATH"
rm -f "$DMG_SHA_PATH"

echo "[4/5] Creating DMG..."
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE_DIR" -ov -format UDZO "$DMG_PATH" >/dev/null
rm -rf "$STAGE_DIR"

echo "[5/5] Writing sha256..."
shasum -a 256 "$DMG_PATH" > "$DMG_SHA_PATH"

echo "DMG created: $DMG_PATH"
echo "DMG sha256: $DMG_SHA_PATH"
