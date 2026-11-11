#!/bin/zsh
# Turns an Xcode archive into a notarized disk image for people who don't use the Mac App Store.
#
#   scripts/make-dmg.sh "<path to .xcarchive>"      ->  build/Right-Shortcuts-<version>.dmg
#
# Needs Xcode, signed in to a paid Apple Developer account. Xcode signs with the account's
# cloud-managed Developer ID certificate and sends the app to Apple's notary service, so no
# certificate or password has to be on this Mac. When xcode-select points at the Command Line
# Tools, set DEVELOPER_DIR to Xcode's Contents/Developer folder.
set -euo pipefail

ROOT="${0:A:h:h}"
ARCHIVE="${1:?usage: make-dmg.sh <path to .xcarchive>}"
APP_NAME="Right Shortcuts"
OUT="$ROOT/build"
WORK="$OUT/dmg"

step() { print -P "%F{magenta}==>%f %B$1%b" }
fail() { print -P "%F{red}error:%f $1"; exit 1 }

[[ -f "$ARCHIVE/Info.plist" ]] || fail "\"$ARCHIVE\" is not an Xcode archive."
xcodebuild -version > /dev/null 2>&1 || fail "xcodebuild needs Xcode. Set DEVELOPER_DIR to Xcode's Contents/Developer folder."
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleShortVersionString' "$ARCHIVE/Info.plist")"
DMG="$OUT/${APP_NAME// /-}-$VERSION.dmg"

rm -rf "$WORK"
mkdir -p "$WORK/image"

# ---------- Sign and notarize ----------
step "Signing with Developer ID and sending to Apple's notary service"
cat > "$WORK/export.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>developer-id</string>
	<key>destination</key>
	<string>upload</string>
</dict>
</plist>
EOF
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$WORK/export.plist" \
    -allowProvisioningUpdates > "$WORK/upload.log" 2>&1 || { tail -20 "$WORK/upload.log"; fail "The upload failed." }

step "Waiting for Apple"
# Until Apple has finished, the export fails with "is processing and not ready for distribution".
for attempt in {1..45}; do
    xcodebuild -exportNotarizedApp -archivePath "$ARCHIVE" -exportPath "$WORK/notarized" \
        > "$WORK/notarized.log" 2>&1 && break
    grep -q "is processing" "$WORK/notarized.log" || { tail -20 "$WORK/notarized.log"; fail "Notarization failed." }
    (( attempt < 45 )) || fail "Apple was still processing after 15 minutes. Run this script again later."
    sleep 20
done
APP="$WORK/notarized/$APP_NAME.app"

# ---------- Check what came back ----------
step "Checking the notarized app"
codesign --verify --deep --strict "$APP"
xcrun stapler validate -q "$APP"
spctl --assess --type execute "$APP"

# ---------- Disk image ----------
step "Building the disk image"
# The image itself is not signed: that needs a Developer ID certificate on this Mac. Gatekeeper
# checks the app inside, which carries Apple's notarization ticket and so also passes offline.
ditto "$APP" "$WORK/image/$APP_NAME.app"
ln -s /Applications "$WORK/image/Applications"
hdiutil create -quiet -ov -volname "$APP_NAME" -srcfolder "$WORK/image" -fs HFS+ -format UDZO "$DMG"
hdiutil verify -quiet "$DMG"

step "Built $DMG"
shasum -a 256 "$DMG"
