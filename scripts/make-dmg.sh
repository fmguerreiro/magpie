#!/bin/bash
# Packages dist/Magpie.app into dist/Magpie.dmg with an Applications symlink for
# drag-to-install. Run scripts/build-app.sh first.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Magpie"
APP="dist/$APP_NAME.app"
DMG="dist/$APP_NAME.dmg"

[ -d "$APP" ] || { echo "missing $APP — run scripts/build-app.sh first" >&2; exit 1; }

staging="$(mktemp -d)"
cp -R "$APP" "$staging/"
ln -s /Applications "$staging/Applications"

rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$staging" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$staging"
echo "made $DMG"
