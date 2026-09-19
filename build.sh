#!/bin/zsh
# Builds Tuck.app into ./build using only the Xcode Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Tuck.app"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "▸ Compiling…"
swiftc -O \
  -target arm64-apple-macosx14.0 \
  -framework Cocoa -framework SwiftUI -framework ServiceManagement \
  -o "$APP/Contents/MacOS/Tuck" \
  Sources/*.swift

cp Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# App icon (optional; skipped if the generator fails)
if [[ -f make-icon.swift ]]; then
  echo "▸ Generating icon…"
  ICONSET="build/AppIcon.iconset"
  mkdir -p "$ICONSET"
  if swift make-icon.swift "build/icon-1024.png" 2>/dev/null; then
    for s in 16 32 128 256 512; do
      sips -z $s $s "build/icon-1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
      d=$((s*2))
      sips -z $d $d "build/icon-1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" || true
  fi
fi

echo "▸ Signing (ad-hoc)…"
# A stable designated requirement keeps the Accessibility grant valid across
# rebuilds (an ad-hoc signature's default requirement changes with every build).
codesign --force --deep --sign - \
  --identifier com.champ.tuck \
  --requirements '=designated => identifier "com.champ.tuck"' \
  "$APP"

echo "✓ Built $APP"
