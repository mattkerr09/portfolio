#!/bin/bash
# Regenerate assets/Matthew_Kerr_Marketing_Resume.pdf from _resume/resume.html.
#
# Why this script exists: on 2026-08-13 the live PDF claimed "5,000+ monthly
# model downloads" while the HTML next to it said "2,500+ across 42 published
# models" and the real figure was 2,669. The HTML had been corrected weeks
# earlier and the PDF was never rebuilt — so the one document that actually goes
# to a hiring manager carried a figure nearly double the truth, on the same
# domain as the corrected page.
#
# The original PDF's own metadata named its producer: HeadlessChrome/150 +
# Skia/PDF, printed from this same HTML. So this reproduces the existing
# document rather than replacing it with a differently-styled one.
set -euo pipefail
cd "$(dirname "$0")/.."
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
SRC="$PWD/_resume/resume.html"
OUT="$PWD/assets/Matthew_Kerr_Marketing_Resume.pdf"

[ -x "$CHROME" ] || { echo "Chrome not found at $CHROME" >&2; exit 1; }
[ -f "$SRC" ]    || { echo "missing $SRC" >&2; exit 1; }

"$CHROME" --headless --disable-gpu --no-pdf-header-footer \
  --print-to-pdf="$OUT" "file://$SRC" 2>/dev/null

[ -s "$OUT" ] || { echo "no PDF produced" >&2; exit 1; }
echo "built $OUT ($(wc -c < "$OUT" | tr -d ' ') bytes)"
