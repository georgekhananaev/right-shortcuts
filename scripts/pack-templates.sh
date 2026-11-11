#!/bin/zsh
# Zips the Office template sources into real .docx, .xlsx and .pptx files.
# Usage: pack-templates.sh <output folder>
set -euo pipefail

ROOT="${0:A:h:h}"
OUT="${1:?usage: pack-templates.sh <output folder>}"
mkdir -p "$OUT"

pack() {
    local source="$ROOT/Resources/Templates/$1" target="$OUT/$2"
    shift 2
    rm -f "$target"
    # [Content_Types].xml goes first, as Office expects.
    (cd "$source" && zip -X -q -r "$target" '[Content_Types].xml' "$@" -x '*.DS_Store')
}
pack Word Blank.docx _rels word
pack Excel Blank.xlsx _rels xl
pack PowerPoint Blank.pptx _rels ppt
