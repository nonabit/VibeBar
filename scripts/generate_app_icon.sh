#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ICONSET_DIR="$ROOT_DIR/Resources/Assets.xcassets/AppIcon.appiconset"
ICONSET_TMP="$(mktemp -d)"
BASE_PNG="$ICONSET_TMP/base-1024.png"

mkdir -p "$ICONSET_DIR"
mkdir -p "$ROOT_DIR/Resources/Assets.xcassets"

cat > "$ICONSET_TMP/draw_icon.swift" <<'SWIFT'
import AppKit
import Foundation

let outPath = CommandLine.arguments[1]
let size = NSSize(width: 1024, height: 1024)
guard let rep = NSBitmapImageRep(
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
) else {
    fatalError("Cannot create bitmap rep")
}
rep.size = size
guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
    fatalError("Cannot create graphics context")
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
defer { NSGraphicsContext.restoreGraphicsState() }

NSColor.clear.setFill()
NSRect(origin: .zero, size: size).fill()

let canvas = NSRect(x: 48, y: 48, width: 928, height: 928)
let bg = NSBezierPath(roundedRect: canvas, xRadius: 210, yRadius: 210)
let grad = NSGradient(colors: [
    NSColor(calibratedRed: 0.05, green: 0.08, blue: 0.15, alpha: 1.0),
    NSColor(calibratedRed: 0.08, green: 0.17, blue: 0.30, alpha: 1.0),
    NSColor(calibratedRed: 0.05, green: 0.30, blue: 0.36, alpha: 1.0),
])!
grad.draw(in: bg, angle: 135)

NSColor.white.withAlphaComponent(0.22).setStroke()
bg.lineWidth = 8
bg.stroke()

func drawTrack(y: CGFloat) {
    let r = NSRect(x: 188, y: y, width: 648, height: 74)
    let path = NSBezierPath(roundedRect: r, xRadius: 37, yRadius: 37)
    NSColor.white.withAlphaComponent(0.16).setFill()
    path.fill()
}

drawTrack(y: 585)
drawTrack(y: 373)

func drawFill(y: CGFloat, ratio: CGFloat, color: NSColor) {
    let width: CGFloat = 648 * max(0.0, min(1.0, ratio))
    let r = NSRect(x: 188, y: y, width: width, height: 74)
    let p = NSBezierPath(roundedRect: r, xRadius: 37, yRadius: 37)
    color.setFill()
    p.fill()
}

drawFill(y: 585, ratio: 0.82, color: NSColor(calibratedRed: 0.22, green: 0.88, blue: 0.59, alpha: 1.0))
drawFill(y: 373, ratio: 0.61, color: NSColor(calibratedRed: 0.17, green: 0.68, blue: 0.94, alpha: 1.0))

let pulse = NSBezierPath(ovalIn: NSRect(x: 772, y: 760, width: 86, height: 86))
NSColor(calibratedRed: 0.99, green: 0.71, blue: 0.28, alpha: 0.96).setFill()
pulse.fill()

let letter = NSMutableParagraphStyle()
letter.alignment = .left
let attr: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 250, weight: .bold),
    .foregroundColor: NSColor.white.withAlphaComponent(0.94),
    .paragraphStyle: letter
]
NSAttributedString(string: "V", attributes: attr).draw(in: NSRect(x: 185, y: 120, width: 260, height: 260))

let png = rep.representation(using: .png, properties: [:])!
try png.write(to: URL(fileURLWithPath: outPath))
SWIFT

swift "$ICONSET_TMP/draw_icon.swift" "$BASE_PNG"

copy_size() {
  local pt="$1"
  local scale="$2"
  local px=$(( pt * scale ))
  local file
  if [[ "$scale" == "1" ]]; then
    file="icon_${pt}x${pt}.png"
  else
    file="icon_${pt}x${pt}@2x.png"
  fi
  sips -z "$px" "$px" "$BASE_PNG" --out "$ICONSET_DIR/$file" >/dev/null
}

copy_size 16 1
copy_size 16 2
copy_size 32 1
copy_size 32 2
copy_size 128 1
copy_size 128 2
copy_size 256 1
copy_size 256 2
copy_size 512 1
copy_size 512 2

cat > "$ICONSET_DIR/Contents.json" <<'JSON'
{
  "images": [
    { "idiom": "mac", "size": "16x16", "scale": "1x", "filename": "icon_16x16.png" },
    { "idiom": "mac", "size": "16x16", "scale": "2x", "filename": "icon_16x16@2x.png" },
    { "idiom": "mac", "size": "32x32", "scale": "1x", "filename": "icon_32x32.png" },
    { "idiom": "mac", "size": "32x32", "scale": "2x", "filename": "icon_32x32@2x.png" },
    { "idiom": "mac", "size": "128x128", "scale": "1x", "filename": "icon_128x128.png" },
    { "idiom": "mac", "size": "128x128", "scale": "2x", "filename": "icon_128x128@2x.png" },
    { "idiom": "mac", "size": "256x256", "scale": "1x", "filename": "icon_256x256.png" },
    { "idiom": "mac", "size": "256x256", "scale": "2x", "filename": "icon_256x256@2x.png" },
    { "idiom": "mac", "size": "512x512", "scale": "1x", "filename": "icon_512x512.png" },
    { "idiom": "mac", "size": "512x512", "scale": "2x", "filename": "icon_512x512@2x.png" }
  ],
  "info": { "version": 1, "author": "xcode" }
}
JSON

cat > "$ROOT_DIR/Resources/Assets.xcassets/Contents.json" <<'JSON'
{
  "info": { "version": 1, "author": "xcode" }
}
JSON

if command -v iconutil >/dev/null 2>&1; then
  ICNS_TMP="$ICONSET_TMP/AppIcon.iconset"
  mkdir -p "$ICNS_TMP"
  cp "$ICONSET_DIR"/*.png "$ICNS_TMP/"
  if ! iconutil -c icns "$ICNS_TMP" -o "$ROOT_DIR/Resources/AppIcon.icns"; then
    rm -f "$ROOT_DIR/Resources/AppIcon.icns"
    echo "提示: iconutil 生成 .icns 失败，已跳过（不影响 Xcode 的 AppIcon 资产）。"
  fi
fi

echo "App icon generated in: $ICONSET_DIR"
