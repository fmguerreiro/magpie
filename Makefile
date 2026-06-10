.PHONY: build app dmg install icon release clean

# Compile the release binary only.
build:
	swift build -c release

# Assemble dist/Magpie.app (build + bundle + icon + ad-hoc sign).
app:
	VERSION="$${VERSION:-1.0}" ./scripts/build-app.sh

# Package dist/Magpie.dmg for distribution.
dmg: app
	./scripts/make-dmg.sh

# Install the built app into ~/Applications and (re)launch it.
install: app
	rm -rf ~/Applications/Magpie.app
	cp -R dist/Magpie.app ~/Applications/Magpie.app
	@echo "installed to ~/Applications/Magpie.app"

# Regenerate AppIcon.icns from scripts/make-icon.swift.
icon:
	swift scripts/make-icon.swift icon-1024.png
	rm -rf AppIcon.iconset && mkdir AppIcon.iconset
	sips -z 16 16     icon-1024.png --out AppIcon.iconset/icon_16x16.png
	sips -z 32 32     icon-1024.png --out AppIcon.iconset/icon_16x16@2x.png
	sips -z 32 32     icon-1024.png --out AppIcon.iconset/icon_32x32.png
	sips -z 64 64     icon-1024.png --out AppIcon.iconset/icon_32x32@2x.png
	sips -z 128 128   icon-1024.png --out AppIcon.iconset/icon_128x128.png
	sips -z 256 256   icon-1024.png --out AppIcon.iconset/icon_128x128@2x.png
	sips -z 256 256   icon-1024.png --out AppIcon.iconset/icon_256x256.png
	sips -z 512 512   icon-1024.png --out AppIcon.iconset/icon_256x256@2x.png
	sips -z 512 512   icon-1024.png --out AppIcon.iconset/icon_512x512.png
	cp icon-1024.png AppIcon.iconset/icon_512x512@2x.png
	iconutil -c icns AppIcon.iconset -o AppIcon.icns

# Cut a release: build the DMG, publish a GitHub release, bump the Homebrew cask.
# Pass the version: make release VERSION=0.1.0
release:
	@test -n "$(VERSION)" || { echo "VERSION is required, e.g. make release VERSION=0.1.0" >&2; exit 1; }
	./scripts/release.sh $(VERSION)

clean:
	rm -rf .build dist AppIcon.iconset
