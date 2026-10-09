#!/bin/bash
# Builds DeepUninstall.app into ./dist
#   ./build.sh            release build
#   ./build.sh --open     build and launch
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="DeepUninstall"
DIST="dist"
APP="$DIST/$APP_NAME.app"

echo "▸ Compiling (release)…"
swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/$APP_NAME"

echo "▸ Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp Bundle/Info.plist "$APP/Contents/Info.plist"
[ -f Bundle/AppIcon.icns ] && cp Bundle/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Localizations: Bundle/Localization/<lang>.lproj/Localizable.strings
if [ -d Bundle/Localization ]; then
  cp -R Bundle/Localization/*.lproj "$APP/Contents/Resources/"
fi

echo "▸ Signing (ad-hoc)"
codesign --force --deep --sign - "$APP"

echo "✓ Built $APP"
if [[ "${1:-}" == "--open" ]]; then open "$APP"; fi
