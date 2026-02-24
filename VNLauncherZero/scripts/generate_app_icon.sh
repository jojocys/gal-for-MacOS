#!/bin/zsh
set -euo pipefail

# 生成 App 图标（.icns）
# 优先使用自定义图片：assets/custom-logo.png（建议 1024x1024 PNG）
# 若未提供自定义图片，则生成默认图标。
# 依赖：swift、sips、iconutil（macOS 自带）
#
# 用法：
#   ./scripts/generate_app_icon.sh

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ASSETS_DIR="$ROOT_DIR/assets"
ICONSET_DIR="$ASSETS_DIR/VNLauncherZero.iconset"
ICNS_PATH="$ASSETS_DIR/VNLauncherZero.icns"
TMP_SWIFT="$ASSETS_DIR/.icon_renderer.swift"
CUSTOM_PNG="$ASSETS_DIR/custom-logo.png"
CUSTOM_RADIUS_ON_1024=40

mkdir -p "$ASSETS_DIR"
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

render_from_custom_png() {
  local src="$1"
  echo "Using custom logo image: $src"

  cat > "$TMP_SWIFT" <<'EOF'
import AppKit
import Foundation

let args = CommandLine.arguments
guard args.count >= 5 else { exit(1) }

let inputPath = args[1]
let size = Int(args[2]) ?? 1024
let baseRadius = Double(args[3]) ?? 20.0
let outputPath = args[4]

let radius = CGFloat(baseRadius) * CGFloat(size) / 1024.0
let destSize = NSSize(width: size, height: size)
let rect = NSRect(origin: .zero, size: destSize)

guard let source = NSImage(contentsOfFile: inputPath) else { exit(2) }

let out = NSImage(size: destSize)
out.lockFocus()

NSGraphicsContext.current?.imageInterpolation = .high

let clipPath = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
clipPath.addClip()
source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)

out.unlockFocus()

guard
  let tiff = out.tiffRepresentation,
  let rep = NSBitmapImageRep(data: tiff),
  let png = rep.representation(using: .png, properties: [:])
else { exit(3) }

try png.write(to: URL(fileURLWithPath: outputPath))
EOF

  render_custom() {
    local px="$1"
    local name="$2"
    swift "$TMP_SWIFT" "$src" "$px" "$CUSTOM_RADIUS_ON_1024" "$ICONSET_DIR/$name"
    # iconutil 对某些 AppKit 输出 PNG 的元数据比较敏感；用 sips 重编码一遍提升兼容性
    sips -s format png "$ICONSET_DIR/$name" --out "$ICONSET_DIR/$name" >/dev/null
  }

  # 标准 macOS iconset 尺寸（套用圆角）
  render_custom 16 icon_16x16.png
  render_custom 32 icon_16x16@2x.png
  render_custom 32 icon_32x32.png
  render_custom 64 icon_32x32@2x.png
  render_custom 128 icon_128x128.png
  render_custom 256 icon_128x128@2x.png
  render_custom 256 icon_256x256.png
  render_custom 512 icon_256x256@2x.png
  render_custom 512 icon_512x512.png
  render_custom 1024 icon_512x512@2x.png
}

render_default_icon_source() {
cat > "$TMP_SWIFT" <<'EOF'
import AppKit
import Foundation

let args = CommandLine.arguments
guard args.count >= 3 else { exit(1) }
let size = Int(args[1]) ?? 1024
let outputPath = args[2]

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let rect = NSRect(x: 0, y: 0, width: size, height: size)
NSColor(calibratedRed: 0.05, green: 0.08, blue: 0.12, alpha: 1).setFill()
rect.fill()

let bgRect = rect.insetBy(dx: CGFloat(size) * 0.07, dy: CGFloat(size) * 0.07)
let path = NSBezierPath(roundedRect: bgRect, xRadius: CGFloat(size) * 0.14, yRadius: CGFloat(size) * 0.14)
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.12, green: 0.78, blue: 0.55, alpha: 1),
    NSColor(calibratedRed: 0.07, green: 0.44, blue: 0.38, alpha: 1)
])!
gradient.draw(in: path, angle: 245)

NSGraphicsContext.current?.saveGraphicsState()
let glow = NSShadow()
glow.shadowBlurRadius = CGFloat(size) * 0.05
glow.shadowOffset = .zero
glow.shadowColor = NSColor(calibratedWhite: 1.0, alpha: 0.15)
glow.set()

let innerRect = bgRect.insetBy(dx: CGFloat(size) * 0.10, dy: CGFloat(size) * 0.10)
let innerPath = NSBezierPath(roundedRect: innerRect, xRadius: CGFloat(size) * 0.11, yRadius: CGFloat(size) * 0.11)
NSColor(calibratedWhite: 1.0, alpha: 0.06).setFill()
innerPath.fill()
NSGraphicsContext.current?.restoreGraphicsState()

// Stylized "VN" mark
let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let attr: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: CGFloat(size) * 0.33, weight: .black),
    .foregroundColor: NSColor.white,
    .paragraphStyle: paragraph
]
let text = NSAttributedString(string: "VN", attributes: attr)
let textRect = NSRect(
    x: 0,
    y: CGFloat(size) * 0.38,
    width: CGFloat(size),
    height: CGFloat(size) * 0.28
)
text.draw(in: textRect)

// Subtitle stripe
let stripeRect = NSRect(
    x: CGFloat(size) * 0.22,
    y: CGFloat(size) * 0.19,
    width: CGFloat(size) * 0.56,
    height: CGFloat(size) * 0.09
)
let stripe = NSBezierPath(roundedRect: stripeRect, xRadius: CGFloat(size) * 0.04, yRadius: CGFloat(size) * 0.04)
NSColor(calibratedRed: 0.98, green: 0.67, blue: 0.20, alpha: 0.95).setFill()
stripe.fill()

let subAttr: [NSAttributedString.Key: Any] = [
    .font: NSFont.monospacedSystemFont(ofSize: CGFloat(size) * 0.045, weight: .bold),
    .foregroundColor: NSColor.black.withAlphaComponent(0.78),
    .paragraphStyle: paragraph
]
let subText = NSAttributedString(string: "ZERO", attributes: subAttr)
subText.draw(in: stripeRect.insetBy(dx: 0, dy: CGFloat(size) * 0.012))

image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let rep = NSBitmapImageRep(data: tiff),
    let png = rep.representation(using: .png, properties: [:])
else { exit(2) }

try png.write(to: URL(fileURLWithPath: outputPath))
EOF

gen_png() {
  local px="$1"
  local name="$2"
  swift "$TMP_SWIFT" "$px" "$ICONSET_DIR/$name"
}

gen_png 16 icon_16x16.png
gen_png 32 icon_16x16@2x.png
gen_png 32 icon_32x32.png
gen_png 64 icon_32x32@2x.png
gen_png 128 icon_128x128.png
gen_png 256 icon_128x128@2x.png
gen_png 256 icon_256x256.png
gen_png 512 icon_256x256@2x.png
gen_png 512 icon_512x512.png
gen_png 1024 icon_512x512@2x.png
}

if [[ -f "$CUSTOM_PNG" ]]; then
  render_from_custom_png "$CUSTOM_PNG"
else
  render_default_icon_source
fi

iconutil -c icns "$ICONSET_DIR" -o "$ICNS_PATH"
rm -f "$TMP_SWIFT"

echo "Generated icon: $ICNS_PATH"
if [[ -f "$CUSTOM_PNG" ]]; then
  echo "Icon source: $CUSTOM_PNG"
else
  echo "Icon source: built-in generated artwork"
fi
