# Common tasks. Everything here except dmg works with only the Xcode Command Line Tools installed.
# For the Mac App Store, archive RightShortcuts.xcodeproj in Xcode instead (see README).
.PHONY: build install run test icon dmg uninstall clean

build:
	./scripts/build.sh

install: build
	./scripts/install.sh

run: install

test:
	./scripts/test.sh

# Redraws the app icon after editing scripts/generate-icon.swift.
icon:
	rm -rf build/AppIcon.iconset && mkdir -p build
	swift scripts/generate-icon.swift build/AppIcon.iconset > /dev/null
	iconutil -c icns build/AppIcon.iconset -o Resources/App/Bundle/AppIcon.icns

# A notarized disk image for a GitHub release, from an Xcode archive (needs Xcode, see README):
#   make dmg ARCHIVE="path/to/Right Shortcuts.xcarchive"
dmg:
	./scripts/make-dmg.sh "$(ARCHIVE)"

uninstall:
	./scripts/uninstall.sh

clean:
	rm -rf build .build
