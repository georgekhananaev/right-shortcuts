#!/bin/zsh
# Builds "build/Right Shortcuts.app" with the Finder extension inside, signed and ready to run.
#
# Environment overrides:
#   VERSION        marketing version (default 1.0.0)
#   BUILD_NUMBER   build number (default: timestamp)
#   SIGN_IDENTITY  codesigning identity (default: first Developer ID Application or Apple Development identity)
#   UNIVERSAL=1    build for Apple silicon and Intel
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"

APP_NAME="Right Shortcuts"
BUNDLE_ID="com.georgekhananaev.RightShortcuts"
EXT_NAME="RightShortcutsFinderExtension"
VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
OUT="$ROOT/build"
APP="$OUT/$APP_NAME.app"
APPEX="$APP/Contents/PlugIns/$EXT_NAME.appex"

step() { print -P "%F{magenta}==>%f %B$1%b" }

# The Command Line Tools' newest SDK needs SwiftUI macro plugins that only ship with Xcode,
# so without Xcode we build against the macOS 26 SDK.
if [[ -z "${SDKROOT:-}" && "$(xcode-select -p)" == *CommandLineTools* ]]; then
    for candidate in /Library/Developer/CommandLineTools/SDKs/MacOSX26*.sdk(N); do
        export SDKROOT="$candidate"
    done
fi

# ---------- Signing identity and App Group ----------
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning \
    | grep -E '"(Developer ID Application|Apple Development):' | head -1 | sed -E 's/.*"(.*)"/\1/' || true)}"
if [[ -n "$IDENTITY" && "$IDENTITY" != "-" ]]; then
    TEAM_ID="$(security find-certificate -c "$IDENTITY" -p | openssl x509 -noout -subject \
        | sed -nE 's/.*OU ?= ?([A-Z0-9]{10}).*/\1/p')"
    if [[ -z "$TEAM_ID" ]]; then
        print -P "%F{red}error:%f couldn't read the team ID from \"$IDENTITY\". Set SIGN_IDENTITY to a valid identity."
        exit 1
    fi
    APP_GROUP="$TEAM_ID.$BUNDLE_ID"
else
    print -P "%F{yellow}warning:%f no signing identity found; signing ad hoc. The app and its Finder extension need a real identity to share settings."
    IDENTITY="-"
    APP_GROUP="$BUNDLE_ID"
fi

# ---------- Compile ----------
step "Compiling ($([[ "${UNIVERSAL:-0}" == 1 ]] && echo universal || uname -m))"
ARCH_FLAGS=()
[[ "${UNIVERSAL:-0}" == 1 ]] && ARCH_FLAGS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCH_FLAGS[@]}"
BIN="$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)"

# ---------- Bundle ----------
step "Assembling $APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APPEX/Contents/MacOS"
cp "$BIN/RightShortcuts" "$APP/Contents/MacOS/RightShortcuts"
cp "$BIN/$EXT_NAME" "$APPEX/Contents/MacOS/$EXT_NAME"

# The plists and entitlements use Xcode's $(NAME) placeholders, so the Xcode project reads the same files.
render() {
    sed -e "s/\$(MARKETING_VERSION)/$VERSION/g" -e "s/\$(CURRENT_PROJECT_VERSION)/$BUILD_NUMBER/g" \
        -e "s/\$(APP_GROUP_ID)/$APP_GROUP/g" "$1" > "$2"
    plutil -lint -s "$2"
}
mkdir -p "$OUT/signing"
render Resources/App/Info.plist "$APP/Contents/Info.plist"
render Resources/FinderExtension/Info.plist "$APPEX/Contents/Info.plist"
render Resources/App/RightShortcuts.entitlements "$OUT/signing/app.entitlements"
render Resources/FinderExtension/FinderExtension.entitlements "$OUT/signing/extension.entitlements"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# ---------- Resources ----------
step "Copying resources"
cp -R Resources/App/Bundle/. "$APP/Contents/Resources/"
mkdir -p "$APPEX/Contents/Resources"
cp -R Resources/FinderExtension/Bundle/. "$APPEX/Contents/Resources/"
find "$APP" -name .DS_Store -delete
scripts/pack-templates.sh "$APP/Contents/Resources/Templates"

# ---------- Sign ----------
step "Signing with: $IDENTITY"
# Developer ID builds get a secure timestamp so they can be notarized; local builds skip the network call.
TIMESTAMP=--timestamp=none
[[ "$IDENTITY" == "Developer ID Application"* ]] && TIMESTAMP=--timestamp
SIGN_FLAGS=(--force --options runtime "$TIMESTAMP" --sign "$IDENTITY")
codesign "${SIGN_FLAGS[@]}" --entitlements "$OUT/signing/extension.entitlements" "$APPEX"
codesign "${SIGN_FLAGS[@]}" --entitlements "$OUT/signing/app.entitlements" "$APP"
codesign --verify --strict --deep "$APP"

step "Built $APP (version $VERSION, build $BUILD_NUMBER)"
