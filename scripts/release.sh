#!/bin/bash
# Cuts a release: builds the DMG, publishes a GitHub release with it attached,
# then bumps version + sha256 in the Homebrew cask and pushes the tap.
#
# Usage: scripts/release.sh <version>      e.g. scripts/release.sh 0.1.0
# Run from a main checkout; the tap defaults to ../homebrew-tap (TAP_DIR override).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
[ -n "$VERSION" ] || { echo "usage: scripts/release.sh <version>  (e.g. 0.1.0)" >&2; exit 1; }
VERSION="${VERSION#v}"
TAG="v$VERSION"

# The published tag points at main, so HEAD must be main and level with the
# remote: that keeps the tagged commit identical to the one the DMG is built
# from, and lets the re-run path below trust the existing tag.
branch="$(git rev-parse --abbrev-ref HEAD)"
[ "$branch" = "main" ] || { echo "release from main (currently on $branch)" >&2; exit 1; }
git fetch -q origin main
head="$(git rev-parse HEAD)"
[ "$head" = "$(git rev-parse origin/main)" ] || { echo "HEAD is not at origin/main — push or pull first" >&2; exit 1; }

REPO="fmguerreiro/magpie"
TAP_DIR="${TAP_DIR:-../homebrew-tap}"
CASK="$TAP_DIR/Casks/magpie.rb"
DMG="dist/Magpie.dmg"

[ -f "$CASK" ] || { echo "cask not found at $CASK — clone the tap or set TAP_DIR" >&2; exit 1; }

VERSION="$VERSION" ./scripts/build-app.sh
./scripts/make-dmg.sh

# Hash the local artifact before any network/tag operation.
checksum="$(shasum -a 256 "$DMG" | awk '{print $1}')"

# Idempotent: re-running after a mid-release failure re-uploads the asset
# rather than dying on "release already exists".
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    # Peel the tag to a commit so the check works for annotated and lightweight
    # tags alike (GitHub's release API can create either).
    git fetch -q origin "refs/tags/$TAG" || { echo "release $TAG exists but its tag is missing on the remote" >&2; exit 1; }
    tagged="$(git rev-parse "FETCH_HEAD^{commit}")"
    [ "$tagged" = "$head" ] || { echo "release $TAG already exists at $tagged, not HEAD — delete it to re-release" >&2; exit 1; }
    gh release upload "$TAG" "$DMG" --repo "$REPO" --clobber
else
    gh release create "$TAG" "$DMG" --repo "$REPO" --title "$TAG" --generate-notes --target main
fi

sed -i '' -E "s/^([[:space:]]*)version \"[^\"]*\"/\1version \"$VERSION\"/" "$CASK"
sed -i '' -E "s/^([[:space:]]*)sha256 \"[^\"]*\"/\1sha256 \"$checksum\"/" "$CASK"

grep -qF "version \"$VERSION\"" "$CASK" || { echo "cask version bump did not apply in $CASK" >&2; exit 1; }
grep -qF "sha256 \"$checksum\"" "$CASK" || { echo "cask sha256 bump did not apply in $CASK" >&2; exit 1; }

git -C "$TAP_DIR" add Casks/magpie.rb
git -C "$TAP_DIR" commit -m "magpie $VERSION"
git -C "$TAP_DIR" push

echo "released $TAG and bumped cask to $VERSION ($checksum)"
