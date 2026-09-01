#!/usr/bin/env bash
# Validate the dependency-free GitHub Pages site.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SITE="$ROOT/site"

required=(
	index.html
	architecture.html
	styles.css
	site.js
	assets/launchlayer.svg
	.nojekyll
)

for file in "${required[@]}"; do
	[[ -f "$SITE/$file" ]] || {
		echo "missing Pages artifact: site/$file" >&2
		exit 1
	}
done

node --check "$SITE/site.js"

if grep -Eq '\.has-js[[:space:]]+\.reveal' "$SITE/styles.css"; then
	echo "site/styles.css: primary content must not use JavaScript-only reveal concealment" >&2
	exit 1
fi
if grep -q 'IntersectionObserver' "$SITE/site.js" && grep -Fq 'querySelectorAll(".reveal")' "$SITE/site.js"; then
	echo "site/site.js: primary content must not use observer-driven reveal classes" >&2
	exit 1
fi

python3 - "$ROOT" <<'PY'
import hashlib
import sys
from pathlib import Path

root = Path(sys.argv[1])
receipt = root / "docs/architecture-diagram.sha256"
for line in receipt.read_text(encoding="utf-8").splitlines():
    expected, relative = line.split(maxsplit=1)
    path = root / relative
    actual = hashlib.sha256(path.read_bytes()).hexdigest()
    if actual != expected:
        print(f"checksum mismatch: {relative}", file=sys.stderr)
        raise SystemExit(1)
PY

python3 - "$SITE/index.html" <<'PY'
import sys
from html.parser import HTMLParser
from pathlib import Path


class SiteParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids = set()
        self.duplicate_ids = set()
        self.links = []
        self.images_without_alt = []
        self.has_main = False
        self.has_skip_link = False
        self.has_h1 = False
        self.has_labeled_button = False
        self.lang = None

    def handle_starttag(self, tag, attrs):
        values = dict(attrs)
        if tag == "html":
            self.lang = values.get("lang")
        if tag == "main":
            self.has_main = True
        if identifier := values.get("id"):
            if identifier in self.ids:
                self.duplicate_ids.add(identifier)
            self.ids.add(identifier)
        if tag == "h1":
            self.has_h1 = True
        if tag == "button" and values.get("aria-label"):
            self.has_labeled_button = True
        if tag == "a" and (href := values.get("href")):
            self.links.append(href)
            if href == "#main":
                self.has_skip_link = True
        if tag == "img" and "alt" not in values:
            self.images_without_alt.append(values.get("src", "<unknown>"))


page = Path(sys.argv[1])
parser = SiteParser()
parser.feed(page.read_text(encoding="utf-8"))

errors = []
if parser.lang != "en":
    errors.append("site/index.html must declare lang=en")
if not parser.has_main:
    errors.append("site/index.html needs a main landmark")
if not parser.has_skip_link:
    errors.append("site/index.html needs a skip link to #main")
if not parser.has_h1:
    errors.append("site/index.html needs one primary heading")
if not parser.has_labeled_button:
    errors.append("site/index.html buttons need accessible names")
if parser.duplicate_ids:
    errors.append("duplicate IDs: " + ", ".join(sorted(parser.duplicate_ids)))
if parser.images_without_alt:
    errors.append("images missing alt: " + ", ".join(parser.images_without_alt))

for link in parser.links:
    if link.startswith("#") and link[1:] not in parser.ids:
        errors.append(f"missing fragment target: {link}")
    elif "://" not in link and not link.startswith(('#', 'mailto:')):
        target = (page.parent / link.split("#", 1)[0]).resolve()
        if not target.exists():
            errors.append(f"missing local link target: {link}")

if errors:
    print("\n".join(errors), file=sys.stderr)
    raise SystemExit(1)
PY

grep -q 'prefers-reduced-motion: reduce' "$SITE/styles.css" || {
	echo "site CSS must handle reduced motion" >&2
	exit 1
}
grep -q ':focus-visible' "$SITE/styles.css" || {
	echo "site CSS must provide visible keyboard focus" >&2
	exit 1
}

echo "Pages site checks passed"
