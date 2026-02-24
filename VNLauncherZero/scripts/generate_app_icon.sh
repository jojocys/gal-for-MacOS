#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ASSETS_DIR="$ROOT_DIR/assets"
ICONSET_DIR="$ASSETS_DIR/AppIcon.iconset"
OUTPUT_ICNS="$ASSETS_DIR/VNLauncherZero.icns"
CUSTOM_ICON="$ASSETS_DIR/custom-logo.png"
ALT_CUSTOM_ICON="$ASSETS_DIR/GAL FOR MacOS logo.png"
TMP_DIR="$(mktemp -d)"
ROUNDED_SRC="$TMP_DIR/rounded-source.png"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$ASSETS_DIR"
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

SOURCE_PNG=""
if [[ -f "$CUSTOM_ICON" ]]; then
  SOURCE_PNG="$CUSTOM_ICON"
elif [[ -f "$ALT_CUSTOM_ICON" ]]; then
  SOURCE_PNG="$ALT_CUSTOM_ICON"
fi

if [[ -n "$SOURCE_PNG" ]]; then
  swift - "$SOURCE_PNG" "$ROUNDED_SRC" <<'SWIFT'
import AppKit
import Foundation

let args = CommandLine.arguments
guard args.count >= 3 else { exit(1) }
let input = URL(fileURLWithPath: args[1])
let output = URL(fileURLWithPath: args[2])
let baseCorner: CGFloat = 60.0

guard let image = NSImage(contentsOf: input) else {
    fputs("Failed to load input image\n", stderr)
    exit(2)
}

let size = NSSize(width: 1024, height: 1024)
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size.width),
    pixelsHigh: Int(size.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!
rep.size = size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let rect = NSRect(origin: .zero, size: size)
NSColor.clear.setFill()
rect.fill()
let clip = NSBezierPath(roundedRect: rect, xRadius: baseCorner, yRadius: baseCorner)
clip.addClip()
image.draw(in: rect, from: .zero, operation: .copy, fraction: 1.0)

NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else {
    fputs("Failed to write PNG\n", stderr)
    exit(3)
}
try data.write(to: output, options: .atomic)
SWIFT
  SOURCE_FOR_SCALE="$ROUNDED_SRC"
else
  SOURCE_FOR_SCALE="$TMP_DIR/default.png"
  swift - "$SOURCE_FOR_SCALE" <<'SWIFT'
import AppKit
import Foundation
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let size = NSSize(width: 1024, height: 1024)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let rect = NSRect(origin: .zero, size: size)
let bg = NSGradient(colors: [NSColor(calibratedRed: 0.08, green: 0.13, blue: 0.27, alpha: 1), NSColor.black])!
bg.draw(in: rect, angle: -25)
let center = NSBezierPath(ovalIn: NSRect(x: 170, y: 190, width: 684, height: 684))
NSColor(calibratedWhite: 1, alpha: 0.08).setFill(); center.fill()
let text = NSString(string: "GAL")
text.draw(at: NSPoint(x: 310, y: 440), withAttributes: [
    .font: NSFont.boldSystemFont(ofSize: 190),
    .foregroundColor: NSColor.white
])
NSGraphicsContext.restoreGraphicsState()
let data = rep.representation(using: .png, properties: [:])!
try data.write(to: output)
SWIFT
fi

function scale_png() {
  local size="$1"
  local name="$2"
  /usr/bin/sips -s format png -z "$size" "$size" "$SOURCE_FOR_SCALE" --out "$ICONSET_DIR/$name" >/dev/null
}

scale_png 16 icon_16x16.png
scale_png 32 icon_16x16@2x.png
scale_png 32 icon_32x32.png
scale_png 64 icon_32x32@2x.png
scale_png 128 icon_128x128.png
scale_png 256 icon_128x128@2x.png
scale_png 256 icon_256x256.png
scale_png 512 icon_256x256@2x.png
scale_png 512 icon_512x512.png
cp "$SOURCE_FOR_SCALE" "$ICONSET_DIR/icon_512x512@2x.png"

/usr/bin/iconutil -c icns "$ICONSET_DIR" -o "$OUTPUT_ICNS"

echo "Generated icon: $OUTPUT_ICNS"
if [[ -n "$SOURCE_PNG" ]]; then
  echo "Icon source: $SOURCE_PNG"
else
  echo "Icon source: default generated artwork"
fi
