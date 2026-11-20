#!/bin/bash
# สร้าง Iris.app (Release, Apple Silicon) ไว้ที่ ./build/Iris.app
set -euo pipefail
cd "$(dirname "$0")"

APP="Iris"
OUT="build/$APP.app"

echo "▸ คอมไพล์ (release)…"
swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/$APP"

echo "▸ ประกอบ $OUT"
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
cp "$BIN" "$OUT/Contents/MacOS/$APP"
cp Resources/Info.plist "$OUT/Contents/Info.plist"

if [ -f Resources/AppIcon.png ]; then
  echo "▸ สร้างไอคอน"
  TMP="$(mktemp -d)"
  ICONSET="$TMP/AppIcon.iconset"
  mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z $s $s Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$OUT/Contents/Resources/AppIcon.icns"
  rm -rf "$TMP"
fi

echo "▸ เซ็นแบบ ad-hoc"
codesign --force --deep --sign - "$OUT"

echo "✅ เสร็จแล้ว: $OUT"
echo "   ติดตั้ง:  cp -R \"$OUT\" /Applications/"
