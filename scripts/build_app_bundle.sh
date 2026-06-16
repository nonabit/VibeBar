#!/usr/bin/env bash
set -euo pipefail

APP_NAME="VibeBar"
BUNDLE_ID="com.vibebar.app"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-debug}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-auto}"
OUTPUT_PATH=""
UNIVERSAL=0

usage() {
  echo "Usage: $0 [--configuration debug|release] [--universal] [--output <path>] [--sign <identity|auto|none>]" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --configuration|-c)
      CONFIGURATION="${2:-}"
      shift 2
      ;;
    --release)
      CONFIGURATION="release"
      shift
      ;;
    --debug)
      CONFIGURATION="debug"
      shift
      ;;
    --universal)
      UNIVERSAL=1
      shift
      ;;
    --output|-o)
      OUTPUT_PATH="${2:-}"
      shift 2
      ;;
    --sign)
      CODE_SIGN_IDENTITY="${2:-}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

case "$CONFIGURATION" in
  debug|release) ;;
  *)
    echo "Error: configuration must be debug or release." >&2
    exit 2
    ;;
esac

if [[ -z "$OUTPUT_PATH" ]]; then
  OUTPUT_PATH="$ROOT_DIR/dist/$APP_NAME.app"
fi

APP_BUNDLE="$OUTPUT_PATH"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$ROOT_DIR/Config/Info.plist" 2>/dev/null || true
}

find_codesign_identity() {
  local preferred="$1"
  local fallback="$2"
  local identities
  identities="$(security find-identity -p codesigning -v 2>/dev/null || true)"

  local identity
  identity="$(printf '%s\n' "$identities" | sed -n "s/.*\"\($preferred[^\"]*\)\".*/\1/p" | head -n 1)"
  if [[ -n "$identity" ]]; then
    echo "$identity"
    return 0
  fi

  identity="$(printf '%s\n' "$identities" | sed -n "s/.*\"\($fallback[^\"]*\)\".*/\1/p" | head -n 1)"
  if [[ -n "$identity" ]]; then
    echo "$identity"
  fi
}

resolve_codesign_identity() {
  case "$CODE_SIGN_IDENTITY" in
    ""|none|skip)
      return 0
      ;;
    auto)
      if [[ "$CONFIGURATION" == "release" ]]; then
        find_codesign_identity "Developer ID Application:" "Apple Development:"
      else
        find_codesign_identity "Apple Development:" "Developer ID Application:"
      fi
      ;;
    *)
      echo "$CODE_SIGN_IDENTITY"
      ;;
  esac
}

build_binary() {
  local triple="$1"
  swift build \
    --package-path "$ROOT_DIR" \
    --configuration "$CONFIGURATION" \
    --product "$APP_NAME" \
    --triple "$triple" >&2
  local bin_path
  bin_path="$(swift build \
    --package-path "$ROOT_DIR" \
    --configuration "$CONFIGURATION" \
    --triple "$triple" \
    --show-bin-path)"
  echo "$bin_path/$APP_NAME"
}

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"

if [[ "$UNIVERSAL" -eq 1 ]]; then
  ARM_BINARY="$(build_binary "arm64-apple-macosx$MIN_SYSTEM_VERSION")"
  X86_BINARY="$(build_binary "x86_64-apple-macosx$MIN_SYSTEM_VERSION")"
  lipo -create "$ARM_BINARY" "$X86_BINARY" -output "$APP_BINARY"
else
  swift build \
    --package-path "$ROOT_DIR" \
    --configuration "$CONFIGURATION" \
    --product "$APP_NAME"
  BUILD_BINARY="$(swift build \
    --package-path "$ROOT_DIR" \
    --configuration "$CONFIGURATION" \
    --show-bin-path)/$APP_NAME"
  cp "$BUILD_BINARY" "$APP_BINARY"
fi

chmod +x "$APP_BINARY"

ICONSET_SOURCE="$ROOT_DIR/Resources/Assets.xcassets/AppIcon.appiconset"
if [[ -d "$ICONSET_SOURCE" ]]; then
  icons=("$ICONSET_SOURCE"/icon_*.png)
  if [[ -e "${icons[0]}" ]]; then
    ICONSET_TMP="$TMP_DIR/AppIcon.iconset"
    mkdir -p "$ICONSET_TMP"
    cp "${icons[@]}" "$ICONSET_TMP"/
    iconutil -c icns "$ICONSET_TMP" -o "$APP_RESOURCES/AppIcon.icns"
  fi
fi

SHORT_VERSION="$(plist_value CFBundleShortVersionString)"
BUILD_VERSION="$(plist_value CFBundleVersion)"
SHORT_VERSION="${SHORT_VERSION:-1.0.0}"
BUILD_VERSION="${BUILD_VERSION:-1}"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh-Hans</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$SHORT_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_VERSION</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.utilities</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

plutil -lint "$INFO_PLIST" >/dev/null

RESOLVED_CODE_SIGN_IDENTITY="$(resolve_codesign_identity)"
if [[ -n "$RESOLVED_CODE_SIGN_IDENTITY" ]]; then
  codesign \
    --force \
    --deep \
    --options runtime \
    --identifier "$BUNDLE_ID" \
    --sign "$RESOLVED_CODE_SIGN_IDENTITY" \
    "$APP_BUNDLE"
else
  echo "Warning: no code signing identity found; $APP_BUNDLE remains unsigned/ad-hoc." >&2
fi

echo "$APP_BUNDLE"
