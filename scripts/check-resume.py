#!/usr/bin/env python3
"""Is the published PDF still saying what the HTML says?

Written 2026-08-13 after the resume PDF on matthewkerr.dev claimed "5,000+
monthly model downloads" while _resume/resume.html — its own source, in the same
repo — said "2,500+ monthly downloads across 42 published models", and the real
figure from the Hugging Face API was 2,669.

The HTML had been corrected. The PDF was never rebuilt. So the correction landed
on the page nobody reads and missed the document that actually gets attached to
job applications, and it sat that way because nothing compared the two.

This does not check the numbers against the world — facts.tsv already does that
for the HTML, and floor:kerr-hf-downloads will fail if the claim ever exceeds
the truth. This checks the narrower thing that was actually broken: whether the
PDF is a faithful render of the HTML it came from. Any drift at all, in any
sentence, means the PDF is stale and scripts/build-resume.sh needs to run.

Compares the two as a single stream of letters and digits, discarding whitespace,
case, punctuation and the ligatures a renderer substitutes — every one of which
produced a false failure while this was being written, and none of which is
content. Exits 1 printing the first place the two diverge.

Usage: python3 scripts/check-resume.py
"""
import html
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
HTML = ROOT / "_resume" / "resume.html"
PDF = ROOT / "assets" / "Matthew_Kerr_Marketing_Resume.pdf"

LIGATURES = {"ﬁ": "fi", "ﬂ": "fl", "ﬀ": "ff",
             "ﬃ": "ffi", "ﬄ": "ffl"}


def normalise(text: str) -> str:
    """Reduce both documents to the same stream of alphanumeric words.

    Everything discarded here is something a renderer legitimately changes
    without the content changing, and each one produced a false failure on the
    way to this version:

      ligatures      "fulfillment" prints as "fulﬁllment"
      case           text-transform: uppercase on the section headings
      hyphenation    "e-commerce" breaks across a line as "e-" + "commerce"
      punctuation    stripping <strong> leaves "(2027) ." where the PDF has
                     "(2027)."
      word gaps      two adjacent blocks extract as "grand rapids midesign
                     build" with the boundary space missing

    Whitespace is dropped entirely rather than normalised, which is what killed
    the last artifact: a renderer's spacing is not content. What survives is the
    letters and digits in order, which is where a stale claim lives. "5,000+"
    and "2,500+" differ here; "(2027)." and "(2027) ." do not.
    """
    for lig, plain in LIGATURES.items():
        text = text.replace(lig, plain)
    return re.sub(r"[^0-9a-z]+", "", text.casefold())


def html_text() -> str:
    raw = HTML.read_text(encoding="utf-8")
    # Body only. <title> is the document's name, not its content, and a printed
    # PDF does not render it — comparing it made the check fail at word 0 on a
    # PDF that was in fact correct, which is a gate that cries wolf on its very
    # first run.
    body = re.search(r"<body[^>]*>(.*)</body>", raw, flags=re.S | re.I)
    raw = body.group(1) if body else raw
    raw = re.sub(r"<(script|style)[^>]*>.*?</\1>", " ", raw, flags=re.S | re.I)
    raw = re.sub(r"<!--.*?-->", " ", raw, flags=re.S)
    return normalise(html.unescape(re.sub(r"<[^>]+>", " ", raw)))


def pdf_text() -> str:
    try:
        import pypdf
    except ImportError:
        print("check-resume: pypdf not installed — cannot verify, and an "
              "unverifiable PDF is not a passing one", file=sys.stderr)
        sys.exit(2)
    reader = pypdf.PdfReader(str(PDF))
    return normalise("".join(p.extract_text() or "" for p in reader.pages))


def main() -> int:
    for path in (HTML, PDF):
        if not path.exists():
            print(f"check-resume: missing {path}", file=sys.stderr)
            return 2

    want, got = html_text(), pdf_text()
    if want == got:
        print(f"check-resume: ok — the PDF renders _resume/resume.html exactly "
              f"({len(want)} characters of content).")
        return 0

    i = next((n for n, (a, b) in enumerate(zip(want, got)) if a != b),
             min(len(want), len(got)))
    lo = max(0, i - 55)
    print("check-resume: the PDF has drifted from its source.")
    print(f"  first difference at character {i} of the content stream:")
    print(f"    html: ...{want[lo:i + 55]}...")
    print(f"    pdf : ...{got[lo:i + 55]}...")
    if len(want) != len(got):
        longer = "html" if len(want) > len(got) else "pdf"
        print(f"  ({longer} is {abs(len(want) - len(got))} characters longer)")
    print("  run scripts/build-resume.sh")
    return 1


if __name__ == "__main__":
    sys.exit(main())
