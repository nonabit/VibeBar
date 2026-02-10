#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "用法: $0 <image-path>" >&2
  exit 2
fi

INPUT="$1"
if [[ ! -f "$INPUT" ]]; then
  echo "错误: 文件不存在 -> $INPUT" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ASSETS_DIR="$ROOT_DIR/Resources/Assets.xcassets"
ICONSET_DIR="$ASSETS_DIR/AppIcon.appiconset"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$ASSETS_DIR" "$ICONSET_DIR"

BASE="$TMP_DIR/base.png"
cp "$INPUT" "$BASE"

# 统一转为 PNG
sips -s format png "$BASE" --out "$BASE" >/dev/null

# 居中裁成正方形
W="$(sips -g pixelWidth "$BASE" | awk '/pixelWidth/{print $2}')"
H="$(sips -g pixelHeight "$BASE" | awk '/pixelHeight/{print $2}')"
if [[ -z "$W" || -z "$H" ]]; then
  echo "错误: 无法读取图片尺寸" >&2
  exit 1
fi

if (( W < H )); then
  SIDE="$W"
else
  SIDE="$H"
fi
sips -c "$SIDE" "$SIDE" "$BASE" --out "$BASE" >/dev/null

# 先放大/缩小到 1024 基准
sips -z 1024 1024 "$BASE" --out "$BASE" >/dev/null

make_icon() {
  local pt="$1"
  local scale="$2"
  local px=$(( pt * scale ))
  local name
  if [[ "$scale" == "1" ]]; then
    name="icon_${pt}x${pt}.png"
  else
    name="icon_${pt}x${pt}@2x.png"
  fi
  sips -z "$px" "$px" "$BASE" --out "$ICONSET_DIR/$name" >/dev/null
}

make_icon 16 1
make_icon 16 2
make_icon 32 1
make_icon 32 2
make_icon 128 1
make_icon 128 2
make_icon 256 1
make_icon 256 2
make_icon 512 1
make_icon 512 2

cat > "$ASSETS_DIR/Contents.json" <<'JSON'
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON

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

if command -v iconutil >/dev/null 2>&1; then
  ICONSET_TMP="$TMP_DIR/AppIcon.iconset"
  mkdir -p "$ICONSET_TMP"
  cp "$ICONSET_DIR"/*.png "$ICONSET_TMP/"
  if ! iconutil -c icns "$ICONSET_TMP" -o "$ROOT_DIR/Resources/AppIcon.icns" >/dev/null 2>&1; then
    rm -f "$ROOT_DIR/Resources/AppIcon.icns"
    echo "提示: iconutil 生成 .icns 失败，已跳过（不影响 Xcode 的 AppIcon 资产）。"
  fi
fi

echo "已导入 AppIcon: $ICONSET_DIR"
echo "建议下一步: xcodegen generate && 在 Xcode 里 Clean + Run"
