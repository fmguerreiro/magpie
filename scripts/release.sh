#!/bin/bash
# Cuts a release: builds the DMG, publishes a GitHub release with it attached,
# then bumps version + sha256 in the Homebrew cask and pushes the tap.
#
# Usage: scripts/release.sh <version>      e.g. scripts/release.sh 0.1.0
# The tap checkout location defaults to ../homebrew-tap; override with TAP_DIR.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
[ -n "$VERSION" ] || { echo "usage: scripts/release.sh <version>  (e.g. 0.1.0)" >&2; exit 1; }
VERSION="${VERSION#v}"
TAG="v$VERSION"

REPO="fmguerreiro/magpie"
TAP_DIR="${TAP_DIR:-../homebrew-tap}"
CASK="$TAP_DIR/Casks/magpie.rb"
DMG="dist/Magpie.dmg"

[ -f "$CASK" ] || { echo "cask not found at $CASK — clone the tap or set TAP_DIR" >&2; exit 1; }

VERSION="$VERSION" ./scripts/build-app.sh
./scripts/make-dmg.sh

git tag "$TAG"
git push origin "$TAG"
gh release create "$TAG" "$DMG" --repo "$REPO" --title "$TAG" --generate-notes

sha="$(shasum -a 256 "$DMG" | awk '{print $1}')"

sed -i '' -E "s/^  version \".*\"/  version \"$VERSION\"/" "$CASK"
sed -i '' -E "s/^  sha256 \".*\"/  sha256 \"$sha\"/" "$CASK"

git -C "$TAP_DIR" add Casks/magpie.rb
git -C "$TAP_DIR" commit -m "magpie $VERSION"
git -C "$TAP_DIR" push

echo "released $TAG and bumped cask to $VERSION ($sha)"
