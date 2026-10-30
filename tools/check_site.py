#!/usr/bin/env python3
"""Static sanity checks for the site, a poor man's Lighthouse that needs no browser.

    python3 tools/check_site.py

Per page: relative links and #fragments resolve, ids are unique, images have alt, width and height,
one <h1>, lang/viewport/title/description present, the skip link target exists, no external script or
stylesheet, no inline event handlers, aria-describedby targets exist, links that share a text but go to different
places say which one they are, and every PNG's real size (read from its header) has the shape of the width and height written in
the HTML (and is never shown larger than it is), and a dark variant is the same size as its light one. Then the weight a first visit transfers (page, CSS, JS, the images a light-scheme browser loads right away,
the biggest i18n file; text counted as gzip, which is how Pages sends it) and the weight of the whole page with the lazy
images, each against a budget.
"""
import getpass
import gzip
import html.parser
import pathlib
import re
import struct
import sys
import urllib.parse

ROOT = pathlib.Path(__file__).resolve().parent.parent
PAGES = ["index.html", "docs.html", "privacy.html", "404.html"]
BUDGET_KB = {"index.html": 300, "docs.html": 100, "privacy.html": 100, "404.html": 10}  # first visit, as sent (text compressed)
FULL_KB = {"index.html": 600, "docs.html": 100, "privacy.html": 100, "404.html": 10}  # with the lazy images
errors, warnings = [], []


class Page(html.parser.HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids, self.refs, self.tags, self.h1 = [], [], [], 0
        self.attrs = []

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        self.tags.append((tag, a))
        if "id" in a:
            self.ids.append(a["id"])
        if tag == "h1":
            self.h1 += 1
        for key in ("href", "src", "srcset"):
            if key in a and a[key]:
                self.refs.append((tag, key, a[key]))


def local(ref):
    return not re.match(r"^([a-z][a-z0-9+.-]*:|//|#$)", ref)


def png_size(rel):
    """Width and height from the PNG header, or None."""
    data = (ROOT / rel).read_bytes()[:24]
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    return struct.unpack(">II", data[16:24])


parsed = {}
for name in PAGES:
    path = ROOT / name
    if not path.exists():
        errors.append(f"{name}: missing")
        continue
    text = path.read_text(encoding="utf-8")
    p = Page()
    p.feed(text)
    parsed[name] = p

    if len(p.ids) != len(set(p.ids)):
        errors.append(f"{name}: duplicate ids {sorted({i for i in p.ids if p.ids.count(i) > 1})}")
    if p.h1 != 1:
        errors.append(f"{name}: {p.h1} h1 elements")
    if not re.search(r'<html[^>]*\slang="', text):
        errors.append(f"{name}: no html lang")
    for needle, what in (('name="viewport"', "viewport"), ("<title", "title")):
        if needle not in text:
            errors.append(f"{name}: no {what}")
    if name != "404.html" and 'name="description"' not in text:
        errors.append(f"{name}: no meta description")
    if re.search(r"\son[a-z]+=", text):
        errors.append(f"{name}: inline event handler")
    if "<img" in text:
        for tag, a in p.tags:
            if tag == "img":
                if "alt" not in a:
                    errors.append(f"{name}: img without alt: {a.get('src')}")
                if not (a.get("width") and a.get("height")):
                    errors.append(f"{name}: img without width/height: {a.get('src')}")
                elif a.get("src", "").endswith(".png") and (ROOT / a["src"]).is_file():
                    # width/height reserve the space before the image loads: same shape as the file, never an upscale
                    real = png_size(a["src"])
                    w, h = int(a["width"]), int(a["height"])
                    if abs(real[0] / real[1] - w / h) > 0.005:
                        errors.append(f"{name}: {a['src']} is {real[0]}x{real[1]} but the HTML says {w}x{h} (another shape: the page would jump)")
                    elif real[0] < w:
                        errors.append(f"{name}: {a['src']} is {real[0]} wide and is shown as {w}")
        sources = [(i, a) for i, (t, a) in enumerate(p.tags) if t == "source" and a.get("srcset", "").endswith(".png")]
        for i, a in sources:  # the dark variant sits in front of its <img>: it has to be the same size, or the page jumps
            img = next((b for t, b in p.tags[i + 1:] if t == "img"), None)
            if img and (ROOT / a["srcset"]).is_file() and png_size(a["srcset"]) != png_size(img["src"]):
                errors.append(f"{name}: {a['srcset']} is {png_size(a['srcset'])}, not the size of {img['src']} {png_size(img['src'])}")
    for tag, a in p.tags:
        if tag in ("script", "link") and a.get("src", a.get("href", "")).startswith(("http://", "https://", "//")) \
                and a.get("rel") not in ("alternate", "canonical", None):
            errors.append(f"{name}: external resource {a}")
        if tag == "script" and a.get("src", "").startswith(("http", "//")):
            errors.append(f"{name}: external script")
        if tag == "a" and a.get("href", "").startswith("http") and "noopener" not in a.get("rel", ""):
            warnings.append(f"{name}: external link without rel=noopener: {a['href']}")
    for tag, a in p.tags:
        if "aria-describedby" in a and a["aria-describedby"] not in p.ids:
            errors.append(f"{name}: aria-describedby={a['aria-describedby']} has no target")
    by_text = {}
    for tag, a in p.tags:
        if tag == "a" and a.get("data-i18n"):
            by_text.setdefault(a["data-i18n"], []).append(a)
    for key, links in by_text.items():
        if len({l.get("href") for l in links}) > 1:
            for l in links:
                if not (l.get("aria-describedby") or l.get("aria-label")):
                    errors.append(f"{name}: several links read '{key}' but go to different places; {l.get('href')} needs aria-describedby")
    if name != "404.html":
        skip = [a for t, a in p.tags if t == "a" and a.get("class") == "skip"]
        if not skip or skip[0]["href"][1:] not in p.ids:
            errors.append(f"{name}: skip link target missing")
        labels = re.findall(r'<label for="(\w+)"', text)
        for lab in labels:
            if lab not in p.ids:
                errors.append(f"{name}: label for={lab} has no control")

# links and fragments
checked = 0
for name, p in parsed.items():
    for tag, key, ref in p.refs:
        refs = [r.split()[0] for r in ref.split(",")] if key == "srcset" else [ref]
        for r in refs:
            if not local(r):
                continue
            checked += 1
            url = urllib.parse.urlsplit(r)
            target = ROOT / (url.path or name)
            if r.endswith("/"):
                continue
            if not target.is_file():
                errors.append(f"{name}: broken {key} {r}")
                continue
            if url.fragment and target.suffix == ".html":
                other = parsed.get(target.name)
                if other is None:
                    q = Page()
                    q.feed(target.read_text(encoding="utf-8"))
                    other = q
                if url.fragment not in other.ids:
                    errors.append(f"{name}: {r} points at a missing id")

# every file the pages and the code refer to by name exists (assets/menu, og image, i18n)
for needed in ("assets/og-image.png", "assets/icon.png", "assets/favicon-32.png", "assets/apple-touch-icon.png",
               "robots.txt", "sitemap.xml", ".nojekyll"):
    if not (ROOT / needed).exists():
        errors.append(f"missing {needed}")

# Nothing of the Mac that made the site: this branch is public, and main's public-safety check does not read it. A
# captured `rh` output can carry the account name in a home or temporary path, also percent-encoded inside a URL.
account = getpass.getuser()
LEAKS = [re.compile(p) for p in (r"/private/(?:tmp|var)/", r"/var/folders/", r"/Users/(?!you\b)[\w.-]+", r"%2F(?:Users|private)%2F",
                                 r"claude-\d{3}/")]
if len(account) >= 3 and account != "you":
    LEAKS.append(re.compile(re.escape(account), re.IGNORECASE))
for path in sorted(ROOT.rglob("*")):
    relative = path.relative_to(ROOT)
    if not path.is_file() or relative.parts[0] in (".git", ".build") or path == pathlib.Path(__file__).resolve() or path.suffix not in (
            ".html", ".css", ".js", ".json", ".txt", ".xml", ".md", ".py", ".svg"):
        continue
    text = path.read_text(encoding="utf-8", errors="replace")
    for leak in LEAKS:
        if found := leak.search(text):
            errors.append(f"{relative}: names something of the Mac that made it: {found.group(0)!r}")

# weight (light scheme): what a visit transfers. GitHub Pages sends text compressed, so text counts as its gzip size and
# images as they are. The language file counted is the biggest one (Tamil, in scripts that take three bytes a letter).
def size(rel):
    return (ROOT / rel).stat().st_size


def sent(rel):
    data = (ROOT / rel).read_bytes()
    if rel.endswith((".html", ".css", ".js", ".json", ".svg", ".xml", ".txt")):
        return len(gzip.compress(data, 6))
    return len(data)


biggest = max((f"i18n/{f.name}" for f in (ROOT / "i18n").glob("*.json")), key=sent)
common = sent("assets/site.css") + sent("assets/icon.png") + sent("assets/favicon-32.png")
for name, p in parsed.items():
    first = full = sent(name)
    if name != "404.html":
        scripts = sum(sent(a["src"]) for t, a in p.tags if t == "script" and a.get("src") and local(a["src"]))
        first += common + scripts + sent(biggest)
        full += common + scripts + sent(biggest)
        eager, lazy = set(), set()
        for tag, a in p.tags:
            if tag == "img" and a.get("src", "").endswith(".png") and "icon.png" not in a["src"]:
                (lazy if a.get("loading") == "lazy" else eager).add(a["src"])
        first += sum(sent(f) for f in eager)
        full += sum(sent(f) for f in eager | lazy)
    print(f"{name:14s} first visit about {first / 1024:6.1f} KB (budget {BUDGET_KB[name]}), whole page {full / 1024:6.1f} KB (budget {FULL_KB[name]})"
          + (f"  [language file counted: {biggest}]" if name == "index.html" else ""))
    if first / 1024 > BUDGET_KB[name]:
        errors.append(f"{name}: first visit {first / 1024:.0f} KB over budget {BUDGET_KB[name]}")
    if full / 1024 > FULL_KB[name]:
        errors.append(f"{name}: whole page {full / 1024:.0f} KB over budget {FULL_KB[name]}")

js = sum(size(f"assets/{f.name}") for f in (ROOT / "assets").glob("*.js")) / 1024
css = size("assets/site.css") / 1024
print(f"css {css:.1f} KB, js {js:.1f} KB, local links checked: {checked}")
for w in sorted(set(warnings)):
    print("warning:", w)
for e in errors:
    print("ERROR:", e)
sys.exit(1 if errors else 0)
