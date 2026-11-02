#!/usr/bin/env bash
# Regenerates the Platform's web icons from the palette, with ImageMagick.
#
#   frontend/tool/regenerate_web_icons.sh
#
# It lives here, not in `web/`, so that `flutter build web` does not ship a build
# script to the server: everything under `web/` is copied into the bundle.
#
# The two colours are `theme.dart`'s own light-palette primitives, so the icon is
# the palette rather than a second brand:
#
#   #1E40AF  _PrimitivesLight.primary   (the action / selected colour)
#   #FFFFFF  _PrimitivesLight.onPrimary (what is written on it)
#
# The mark is three rows on a rounded square — a register, which is what this
# Platform mostly is. `any` keeps the rounded square on a transparent canvas;
# `maskable` fills the whole square so a browser's own mask crops it safely, and
# its rows sit inside the central 45%, well within the 80% safe circle.
#
# `test/web_assets_test.dart` re-measures every file this writes against the
# manifest, so a re-run that produced the wrong size fails the suite.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

BRAND='#1E40AF'
INK='#FFFFFF'
OUT=web/icons

# The mark, at 512: three white rows, the last one short.
rows=(
  'roundrectangle 140,176 372,216 20,20'
  'roundrectangle 140,236 372,276 20,20'
  'roundrectangle 140,296 300,336 20,20'
)

draw_mark=()
for row in "${rows[@]}"; do
  draw_mark+=(-fill "$INK" -draw "$row")
done

# `any`: the rounded square, transparent outside it.
convert -size 512x512 xc:none \
  -fill "$BRAND" -draw 'roundrectangle 0,0 511,511 112,112' \
  "${draw_mark[@]}" \
  -strip PNG32:"$OUT/Icon-512.png"

convert "$OUT/Icon-512.png" -resize 192x192 -strip PNG32:"$OUT/Icon-192.png"
# Flutter's own convention for the browser tab's picture: `web/favicon.png`,
# beside the `index.html` that links it.
convert "$OUT/Icon-512.png" -resize 64x64 -strip PNG32:web/favicon.png

# `maskable`: full-bleed, so the browser's mask has something to crop.
convert -size 512x512 "xc:$BRAND" "${draw_mark[@]}" -strip PNG32:"$OUT/Icon-maskable-512.png"
convert "$OUT/Icon-maskable-512.png" -resize 192x192 -strip PNG32:"$OUT/Icon-maskable-192.png"

identify "$OUT"/Icon-192.png "$OUT"/Icon-512.png \
  "$OUT"/Icon-maskable-192.png "$OUT"/Icon-maskable-512.png web/favicon.png
