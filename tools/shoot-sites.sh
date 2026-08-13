#!/usr/bin/env bash
# Re-capture the product screenshots this portfolio shows.
#
# WHY THIS EXISTS. On 2026-08-13 the Docket screenshot on matthewkerr.dev was
# four days old and showed a DIFFERENT DESIGN of the product: dark ground, amber
# accents, an older check count and a retired price. docketseo.app is light with
# an indigo accent. The Crisp screenshot was six weeks old and showed a hero that
# no longer exists — its pill read "100% offline · Apple Silicon · No
# subscription" and it carried two calls to action, where the live site now reads
# "Notarized by Apple" and has one.
#
# Neither was caught by anything, and could not have been. site-price-gate reads
# text and a screenshot is pixels; drift.py compares a published number against a
# command that derives it, and no command reads a picture. Every automated check
# here is blind to the largest, most prominent element on the page. A recruiter
# looking at this site sees the screenshot before any sentence.
#
# The deeper problem was not that the images were old. It was that they were
# captured BY HAND, once, with no way to repeat it — so "regenerate them" was
# never a command anybody could run, and the only fix available was to notice by
# eye. That is why this is a script and not a one-off re-shoot.
#
# The same asset lives in kerr-and-company. Both copies are captured from the
# same live sites, so both go stale on the same day and neither knows about the
# other. Run this after any significant redesign of a product site.
#
#   ./tools/shoot-sites.sh            # all four
#   ./tools/shoot-sites.sh crisp      # just one
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$HERE/assets"
# Playwright is not a dependency of this repo and does not need to be; borrow the
# one the Outlier repo already installs for its end-to-end tests.
PW="/Users/matthewkerr/Projects/Outlier/node_modules/.bin/playwright"
[ -x "$PW" ] || { echo "✗ playwright not found at $PW" >&2; exit 1; }

declare -a NAMES=(crisp outlier docket proposalai)
declare -a URLS=(https://crispvideo.app/ https://outlier.host/ https://docketseo.app/ https://proposalai.app/)

WANT="${1:-all}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"; rm -f /Users/matthewkerr/Projects/Outlier/.shoot-sites.tmp.js' EXIT

for i in "${!NAMES[@]}"; do
  name="${NAMES[$i]}"; url="${URLS[$i]}"
  [ "$WANT" = "all" ] || [ "$WANT" = "$name" ] || continue

  echo "==> $name  $url"
  # The script has to LIVE in the Outlier repo, not just run with it as cwd:
  # node resolves require() from the script's own directory, so a file in /tmp
  # cannot see node_modules no matter where you launch it from.
  SHOOT="/Users/matthewkerr/Projects/Outlier/.shoot-sites.tmp.js"
  cat > "$SHOOT" <<JS
const { chromium } = require('playwright');
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1440, height: 1200 },
                              deviceScaleFactor: 1 });
  await p.goto('${url}', { waitUntil: 'networkidle', timeout: 60000 });
  // Scroll the whole page once so lazy images and scroll-triggered reveals fire.
  // Without this the capture is a tall page of empty placeholders, which looks
  // exactly like a working screenshot of a broken site.
  await p.evaluate(async () => {
    await new Promise(res => {
      let y = 0;
      const step = () => {
        window.scrollTo(0, y);
        y += 800;
        if (y < document.body.scrollHeight) setTimeout(step, 60); else res();
      };
      step();
    });
  });
  await p.evaluate(() => window.scrollTo(0, 0));
  // Force scroll-reveal content visible. outlier.host hides everything below the
  // fold behind \`.reveal{opacity:0;transform:translateY(26px)}\` and un-hides it
  // with an IntersectionObserver. A fullPage screenshot renders the whole
  // document at once rather than scrolling through it, so the observer never
  // fires for most of the page and the capture came back blank from y1500 to
  // y12000 — 10,500px of nothing, in a file that passed every check because it
  // was the right height and a plausible size.
  await p.addStyleTag({ content: \`
    .reveal, [data-reveal] { opacity: 1 !important; transform: none !important; }
    *, *::before, *::after {
      animation-duration: 0s !important; animation-delay: 0s !important;
      transition-duration: 0s !important; transition-delay: 0s !important;
    }\` });
  await p.waitForTimeout(1200);
  await p.screenshot({ path: '$TMP/${name}.png', fullPage: true });
  await b.close();
})();
JS
  ( cd /Users/matthewkerr/Projects/Outlier && node "$SHOOT" )
  rm -f "$SHOOT"

  # Refuse to overwrite with something obviously wrong. A capture that is mostly
  # blank, or absurdly short, means the page did not render — and shipping that
  # is worse than shipping a stale image, because a stale image at least looks
  # like a product.
  H="$(sips -g pixelHeight "$TMP/${name}.png" | awk '/pixelHeight/{print $2}')"
  if [ "$H" -lt 2000 ]; then
    echo "   ✗ capture is only ${H}px tall — the page probably did not render; keeping the old file" >&2
    continue
  fi

  # Height alone is not enough, and I know that because the height check passed a
  # capture of outlier.host that was blank from y1500 to y12000: full height,
  # plausible file size, and 10,500px of nothing.
  #
  # Total ink is not enough either. I tried that next and tested it against a
  # synthetic hero-on-an-empty-page, which scored 6.8% and would have sailed
  # through a 6% floor — while proposalai.app, which is fine, sits at 9.6%. Any
  # threshold that rejects the broken one also rejects a legitimately sparse page.
  #
  # So measure DISTRIBUTION instead, which is what actually distinguishes them. A
  # real page has content most of the way down; a page whose reveals never fired
  # has a full hero, a full footer, and a void between. Fail if more than a third
  # of the vertical bands are empty. Background is taken from the page's own modal
  # colour, so this works on dark and light grounds alike.
  BLANK="$(python3 - "$TMP/${name}.png" <<'PY'
import sys
from collections import Counter
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB")
w, h = im.size
small = im.resize((120, 240))
bg = Counter(list(small.getdata())).most_common(1)[0][0]
bands, empty = 24, 0
for b in range(bands):
    strip = small.crop((0, b * 240 // bands, 120, (b + 1) * 240 // bands))
    d = list(strip.getdata())
    ink = sum(1 for p in d
              if abs(p[0]-bg[0]) + abs(p[1]-bg[1]) + abs(p[2]-bg[2]) > 30)
    if 100 * ink / len(d) < 2:
        empty += 1
print(f"{100*empty/bands:.0f}")
PY
)"
  if [ "$BLANK" -gt 33 ]; then
    echo "   ✗ ${BLANK}% of this capture is empty bands — the page rendered but its" >&2
    echo "     content did not (scroll reveals that never fired). Keeping the old file." >&2
    continue
  fi

  # Encode to real WebP. The first version of this fell back to
  # `sips -s format jpeg ... --out something.webp`, which cheerfully wrote JPEG
  # bytes into a file named .webp: 1.5 MB where the hand-made original was 205 KB,
  # and mislabelled besides. Browsers sniff the content type so it would have
  # rendered, which is exactly why nobody would have noticed. sips on this machine
  # has no WebP encoder, so Pillow does it — and if neither is available the old
  # file is kept rather than replaced with something worse.
  if cwebp -quiet -q 82 "$TMP/${name}.png" -o "$TMP/${name}.webp" 2>/dev/null; then
    :
  elif python3 -c "
from PIL import Image
Image.open('$TMP/${name}.png').save('$TMP/${name}.webp', 'WEBP', quality=82, method=5)
" 2>/dev/null; then
    :
  else
    echo "   ✗ no WebP encoder (install cwebp, or pip install Pillow) — keeping the old file" >&2
    continue
  fi
  mv "$TMP/${name}.webp" "$OUT/${name}-site.webp"
  W="$(sips -g pixelWidth "$TMP/${name}.png" | awk '/pixelWidth/{print $2}')"
  echo "   ✓ $OUT/${name}-site.webp  ${W}x${H}"
  echo "     the <img> width/height attributes must match, or the page reserves"
  echo "     the wrong space and the layout shifts as it loads"
done

echo
echo "Now update width/height in index.html for anything whose size changed,"
echo "and copy to ~/kerr-and-company/assets/ — it shows the same screenshots."
