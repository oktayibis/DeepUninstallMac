#!/bin/bash
# Packages DeepUninstall.app into a .dmg and .zip in ./dist
set -euo pipefail
cd "$(dirname "$0")"

./build.sh

APP_NAME="DeepUninstall"
DIST="dist"
APP="$DIST/$APP_NAME.app"
DMG="$DIST/$APP_NAME.dmg"
ZIP="$DIST/$APP_NAME.zip"

echo "▸ Preparing DMG contents..."
DMG_STAGING="$DIST/dmg_staging"
rm -rf "$DMG_STAGING" "$DMG" "$ZIP"
mkdir -p "$DMG_STAGING"

cp -R "$APP" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

echo "▸ Creating $DMG..."
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGING" -ov -format UDZO "$DMG"
rm -rf "$DMG_STAGING"

echo "▸ Creating $ZIP (preserving permissions and signatures)..."
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "✓ Artifacts created successfully in $DIST/:"
ls -lh "$DMG" "$ZIP"
