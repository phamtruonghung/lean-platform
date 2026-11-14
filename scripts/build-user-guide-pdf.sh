#!/usr/bin/env bash
# Rebuild the user guide's PDF: diagram PNGs, then the PDF itself.
#
#   bash scripts/build-user-guide-pdf.sh
#
# Output:
#   docs/user-guide/images/*.png              diagrams, from docs/user-guide/diagrams/*.html
#   docs/user-guide/pdf/huong-dan-su-dung.pdf the printable guide
#
# Needs, in this order:
#   node    + the playwright package under $HOME/.hermes/skills/creative/deck-design-pdf
#   python3 + the `markdown` module
#   Chromium (the ms-playwright build is used when present; set CHROME to override)
#   ImageMagick `convert` (optional — without it the PDF embeds the full-size PNGs)
#
# The Markdown files are the source of truth. Never hand-edit the PNG or the PDF:
# edit docs/user-guide/*.md or docs/user-guide/diagrams/*.html and run this.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UG="$REPO_ROOT/docs/user-guide"

command -v node >/dev/null || { echo "node not found — needed to render the diagrams" >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 not found — needed to build the PDF" >&2; exit 1; }

echo "== diagrams =="
node "$UG/diagrams/render.js"

echo
echo "== pdf =="
python3 "$UG/tools/build_pdf.py" "$@"
