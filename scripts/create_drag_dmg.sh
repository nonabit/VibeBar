#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <app-path> <output-dmg-path> [volume-name]" >&2
  exit 2
fi

APP_PATH="$1"
OUTPUT_DMG="$2"
VOLUME_NAME="${3:-VibeBar}"
CREATE_DMG_VERSION="${CREATE_DMG_VERSION:-7.1.0}"

if [[ ! -d "$APP_PATH" || "${APP_PATH##*.}" != "app" ]]; then
  echo "Error: app bundle not found -> $APP_PATH" >&2
  exit 2
fi

if ! command -v npx >/dev/null 2>&1 && ! command -v create-dmg >/dev/null 2>&1; then
  echo "Error: create-dmg requires Node.js (npx) or a globally installed create-dmg." >&2
  exit 2
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

OUT_DIR="$WORK_DIR/out"
mkdir -p "$OUT_DIR"

if command -v create-dmg >/dev/null 2>&1; then
  create-dmg "$APP_PATH" "$OUT_DIR" \
    --overwrite \
    --dmg-title="$VOLUME_NAME" \
    --no-code-sign
else
  npx --yes "create-dmg@${CREATE_DMG_VERSION}" "$APP_PATH" "$OUT_DIR" \
    --overwrite \
    --dmg-title="$VOLUME_NAME" \
    --no-code-sign
fi

GENERATED_DMG="$(find "$OUT_DIR" -maxdepth 1 -type f -name '*.dmg' | head -n 1)"
if [[ -z "$GENERATED_DMG" ]]; then
  echo "Error: create-dmg did not generate a .dmg file." >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_DMG")"
rm -f "$OUTPUT_DMG"
mv "$GENERATED_DMG" "$OUTPUT_DMG"

echo "DMG created: $OUTPUT_DMG"
