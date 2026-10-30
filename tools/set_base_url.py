#!/usr/bin/env python3
"""Sets the site's public address once, so search engines and link previews get absolute URLs.

    python3 tools/set_base_url.py https://<user>.github.io/right-here/     set (can be re-run with another URL)
    python3 tools/set_base_url.py --reset                                 back to relative URLs and the placeholder

What it rewrites:
- every element with a data-abs="<relative path>" attribute in the HTML pages: canonical, hreflang,
  og:url, og:image and twitter:image get base + path (the path stays in data-abs, so re-running works);
- sitemap.xml and robots.txt, which it regenerates from the page list below;
- the home link of 404.html (a 404 page is served from any depth, so it needs an absolute link).

The committed state uses relative URLs and PLACEHOLDER in sitemap.xml and robots.txt, so the site
works from any address and from file:// without running this. Run it once the final address is known.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PLACEHOLDER = "https://example.invalid/right-here/"
PAGES = ["index.html", "docs.html", "privacy.html"]
LANGUAGES = ["ar", "bn", "de", "el", "en", "es", "fa", "fr", "he", "hi", "id", "it", "ja", "ko", "mr", "ms",
             "nl", "pl", "pt-BR", "ro", "ru", "ta", "te", "th", "tr", "uk", "ur", "vi", "zh-Hans", "zh-Hant"]


def main():
    args = sys.argv[1:]
    if len(args) != 1:
        sys.exit(__doc__)
    if args[0] == "--reset":
        base = None
        site = PLACEHOLDER
    else:
        site = args[0]
        if not re.match(r"^https?://[^\s/]+(/[^\s?#]*)?$", site):
            sys.exit("The base URL must look like https://user.github.io/right-here/")
        if not site.endswith("/"):
            site += "/"
        base = site

    tag = re.compile(r"<(link|meta)\b[^>]*\sdata-abs=\"([^\"]*)\"[^>]*>")

    def rewrite(m):
        element, rel = m.group(0), m.group(2)
        attr = "content" if m.group(1) == "meta" else "href"
        value = (base + rel) if base else rel
        return re.sub(rf'\s{attr}="[^"]*"', f' {attr}="{value}"', element, count=1)

    for page in PAGES + ["404.html"]:
        path = ROOT / page
        text = path.read_text(encoding="utf-8")
        anchor = re.compile(r"<a\b[^>]*\sdata-abs=\"([^\"]*)\"[^>]*>")
        new = tag.sub(rewrite, text)
        new = anchor.sub(lambda m: re.sub(r'\shref="[^"]*"', f' href="{(base + m.group(1)) if base else "./"}"', m.group(0), count=1), new)
        if new != text:
            path.write_text(new, encoding="utf-8")

    urls = []
    for page in PAGES:
        alternates = "".join(
            f'\n    <xhtml:link rel="alternate" hreflang="{c}" href="{site}{page}?lang={c}"/>' for c in LANGUAGES)
        urls.append(f"  <url>\n    <loc>{site}{page}</loc>{alternates}\n  </url>")
    sitemap = ('<?xml version="1.0" encoding="UTF-8"?>\n'
               '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">\n'
               + "\n".join(urls) + "\n</urlset>\n")
    (ROOT / "sitemap.xml").write_text(sitemap, encoding="utf-8")
    (ROOT / "robots.txt").write_text(f"User-agent: *\nAllow: /\n\nSitemap: {site}sitemap.xml\n", encoding="utf-8")
    print("base URL:", base or f"(reset; placeholder {PLACEHOLDER} in sitemap.xml and robots.txt)")


main()
