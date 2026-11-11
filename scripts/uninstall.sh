#!/bin/zsh
# Removes Right Shortcuts from /Applications. Pass --purge to also delete its settings.
set -euo pipefail

DEST="/Applications/Right Shortcuts.app"
EXT_ID="com.georgekhananaev.RightShortcuts.FinderExtension"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

pluginkit -e ignore -i "$EXT_ID" 2>/dev/null || true
pkill -x RightShortcuts 2>/dev/null || true
pkill -x RightShortcutsFinderExtension 2>/dev/null || true
if [[ -d "$DEST" ]]; then
    pluginkit -r "$DEST/Contents/PlugIns/RightShortcutsFinderExtension.appex" 2>/dev/null || true
    "$LSREGISTER" -u "$DEST" 2>/dev/null || true
    rm -rf "$DEST"
fi

if [[ "${1:-}" == "--purge" ]]; then
    rm -rf ~/Library/Group\ Containers/*.com.georgekhananaev.RightShortcuts
    rm -rf ~/Library/Application\ Scripts/com.georgekhananaev.RightShortcuts*
    defaults delete com.georgekhananaev.RightShortcuts 2>/dev/null || true
    # macOS guards app containers; removing them needs Full Disk Access for the terminal.
    leftovers=()
    for container in ~/Library/Containers/com.georgekhananaev.RightShortcuts*(N); do
        rm -rf "$container" 2>/dev/null || leftovers+=("$container")
    done
    echo "Removed Right Shortcuts and its settings."
    if (( ${#leftovers} )); then
        echo "macOS wouldn't let this script delete these folders. Move them to the Trash in Finder:"
        printf '  %s\n' "${leftovers[@]}"
    fi
else
    echo "Removed Right Shortcuts. Settings were kept; run with --purge to delete them too."
fi
