#!/bin/zsh
set -euo pipefail

# P3: 将 dist/GAL FOR MacOS.app 打包为 .dmg（开发者侧脚本）
# 用法：
#   ./scripts/make_dmg.sh

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_PATH="$DIST_DIR/GAL FOR MacOS.app"
DMG_PATH="$DIST_DIR/GAL FOR MacOS.dmg"
STAGE_DIR="$DIST_DIR/dmg-stage"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH"
  echo "Run ./scripts/build_release_app.sh first."
  exit 1
fi

command -v hdiutil >/dev/null 2>&1 || {
  echo "hdiutil not found."
  exit 1
}

rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
cp -R "$APP_PATH" "$STAGE_DIR/"

rm -f "$DMG_PATH"
hdiutil create \
  -volname "GAL FOR MacOS" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "Created: $DMG_PATH"
