#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_icon="$root/site/favicon.svg"

command -v magick >/dev/null || { echo "ImageMagick is required" >&2; exit 1; }
magick -background none -depth 8 "$source_icon" -resize 180x180 -strip "$root/site/apple-touch-icon.png"
magick -background none -depth 8 "$source_icon" -resize 192x192 -strip "$root/site/icon-192.png"
magick -background none -depth 8 "$source_icon" -resize 512x512 -strip "$root/site/icon-512.png"
