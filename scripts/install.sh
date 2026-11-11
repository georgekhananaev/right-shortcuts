#!/bin/zsh
# Installs the built app into /Applications, registers and enables the Finder extension, and launches it.
set -euo pipefail

ROOT="${0:A:h:h}"
SOURCE="$ROOT/build/Right Shortcuts.app"
DEST="/Applications/Right Shortcuts.app"
EXT_ID="com.georgekhananaev.RightShortcuts.FinderExtension"
EXT_PATH="Contents/PlugIns/RightShortcutsFinderExtension.appex"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

step() { print -P "%F{magenta}==>%f %B$1%b" }

[[ -d "$SOURCE" ]] || "$ROOT/scripts/build.sh"

step "Stopping the running copy"
pkill -x RightShortcuts 2>/dev/null || true
pkill -x RightShortcutsFinderExtension 2>/dev/null || true

step "Copying to /Applications"
rm -rf "$DEST"
ditto "$SOURCE" "$DEST"

step "Registering the Finder extension"
# Forget the copy in build/ so Finder and LaunchServices only ever use the installed app.
pluginkit -r "$SOURCE/$EXT_PATH" 2>/dev/null || true
"$LSREGISTER" -u "$SOURCE" 2>/dev/null || true
"$LSREGISTER" -f -R -trusted "$DEST"
pluginkit -a "$DEST/$EXT_PATH"
pluginkit -e use -i "$EXT_ID"

step "Launching"
open "$DEST"
pluginkit -m -i "$EXT_ID"
