#!/usr/bin/env python3
"""Authoring helper (not needed to serve the site): writes index.html, docs.html and privacy.html.

    python3 tools/render_pages.py

The page structure lives in this file; the English text is filled in from i18n/en.json, so the HTML
and the English source cannot drift (tools/check_i18n.py verifies that). Other languages are applied in
the browser by assets/site.js. Edit a sentence in i18n/en.json, re-run this, translate the key.
"""
import html, json, re, sys, pathlib

ROOT = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else pathlib.Path(__file__).resolve().parent.parent
EN = json.loads((ROOT / "i18n/en.json").read_text(encoding="utf-8"))

LANGS = [
    ("ar", "العربية"), ("bn", "বাংলা"), ("de", "Deutsch"), ("el", "Ελληνικά"), ("en", "English"),
    ("es", "Español"), ("fa", "فارسی"), ("fr", "Français"), ("he", "עברית"), ("hi", "हिन्दी"),
    ("id", "Bahasa Indonesia"), ("it", "Italiano"), ("ja", "日本語"), ("ko", "한국어"), ("mr", "मराठी"),
    ("ms", "Bahasa Melayu"), ("nl", "Nederlands"), ("pl", "Polski"), ("pt-BR", "Português (Brasil)"),
    ("ro", "Română"), ("ru", "Русский"), ("ta", "தமிழ்"), ("te", "తెలుగు"), ("th", "ไทย"),
    ("tr", "Türkçe"), ("uk", "Українська"), ("ur", "اردو"), ("vi", "Tiếng Việt"),
    ("zh-Hans", "简体中文"), ("zh-Hant", "繁體中文"),
]


def rich(text):
    parts = text.split("`")
    return "".join(f"<code>{html.escape(p, quote=False)}</code>" if i % 2 else html.escape(p, quote=False)
                   for i, p in enumerate(parts))


def plain(text):
    return html.escape(text.replace("`", ""), quote=True)


def fill(page):
    used = set()

    def body(m):
        tag, attrs, key, rest = m.group(1), m.group(2), m.group(3), m.group(4)
        used.add(key)
        text = EN[key]
        inner = plain(text).replace("&quot;", '"').replace("&#x27;", "'") if tag == "title" else rich(text)
        return f'<{tag}{attrs} data-i18n="{key}"{rest}>{inner}</{tag}>'

    page = re.sub(r'<(\w+)([^>]*?)\sdata-i18n="([^"]+)"([^>]*)></\1>', body, page)

    def attr(m):
        name, key = m.group(1), m.group(2)
        used.add(key)
        return f'data-i18n-{name}="{key}" {name}="{plain(EN[key])}"'

    page = re.sub(r'data-i18n-([a-z-]+)="([^"]+)"', attr, page)
    return page, used


OG_TITLE = "Right Here: send a folder to your terminals, editors and AI agents"
OG_DESC = "Right-click a folder in Finder. Open it in your terminal, your editor or an AI agent. Free and open source."


def head(page_file, title_key, desc_key):
    # data-abs: tools/set_base_url.py turns these into absolute URLs once the final address is known.
    alt = "\n".join(
        f'<link rel="alternate" hreflang="{c}" href="{page_file}?lang={c}" data-abs="{page_file}?lang={c}">'
        for c, _ in LANGS)
    return f"""<!doctype html>
<html lang="en" dir="ltr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title data-i18n="{title_key}"></title>
<meta name="description" data-i18n-content="{desc_key}">
<meta name="color-scheme" content="light dark">
<link rel="icon" type="image/png" sizes="32x32" href="assets/favicon-32.png">
<link rel="icon" type="image/png" sizes="128x128" href="assets/icon.png">
<link rel="apple-touch-icon" href="assets/apple-touch-icon.png">
<link rel="canonical" href="{page_file}" data-abs="{page_file}">
<meta property="og:type" content="website">
<meta property="og:site_name" content="Right Here">
<meta property="og:title" content="{OG_TITLE}">
<meta property="og:description" content="{OG_DESC}">
<meta property="og:url" content="{page_file}" data-abs="{page_file}">
<meta property="og:image" content="assets/og-image.png" data-abs="assets/og-image.png">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:image:alt" content="Right Here: send a folder to your terminals, editors and AI agents.">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="{OG_TITLE}">
<meta name="twitter:description" content="{OG_DESC}">
<meta name="twitter:image" content="assets/og-image.png" data-abs="assets/og-image.png">
<link rel="stylesheet" href="assets/site.css">
{alt}
<link rel="alternate" hreflang="x-default" href="{page_file}" data-abs="{page_file}">
</head>
<body id="top">
<a class="skip" href="#main" data-i18n="skip"></a>
"""


def header():
    opts = "\n".join(
        f'<option value="{c}" lang="{c}">{n}</option>' for c, n in LANGS)
    return f"""<header class="site-header">
<div class="wrap">
<a class="brand" href="index.html" data-keep-lang data-i18n-aria-label="brand.home"><img src="assets/icon.png" width="32" height="32" alt=""><span>Right Here</span></a>
<nav class="nav" data-i18n-aria-label="nav.label">
<a href="index.html#what" data-keep-lang data-i18n="nav.what"></a>
<a href="index.html#try" data-keep-lang data-i18n="nav.try"></a>
<a href="index.html#setup" data-keep-lang data-i18n="nav.start"></a>
<a href="index.html#how" data-keep-lang data-i18n="nav.how"></a>
<a href="index.html#ai" data-keep-lang data-i18n="nav.ai"></a>
<a href="docs.html" data-keep-lang data-i18n="nav.docs"></a>
<a href="https://github.com/boyugou/right-here" rel="noopener" data-i18n="nav.github"></a>
</nav>
<div class="lang">
<label for="lang" data-i18n="lang.label"></label>
<select id="lang" name="lang">
{opts}
</select>
</div>
</div>
<div class="wrap"><p id="lang-status" class="status-msg" role="status" hidden></p></div>
</header>
"""


def footer(scripts=("site.js",)):
    tags = "\n".join(f'<script src="assets/{name}"></script>' for name in scripts)
    return """<footer class="site-footer">
<div class="wrap">
<span data-i18n="footer.license2"></span>
<nav>
<a href="docs.html" data-keep-lang data-i18n="footer.docs"></a>
<a href="privacy.html" data-keep-lang data-i18n="footer.privacy"></a>
<a href="https://github.com/boyugou/right-here/security/policy" rel="noopener" data-i18n="footer.security"></a>
<a href="https://github.com/boyugou/right-here" rel="noopener" data-i18n="footer.source"></a>
<a href="https://github.com/boyugou/right-here/blob/main/ROADMAP.md" rel="noopener" data-i18n="footer.roadmap"></a>
<a href="#top" data-i18n="footer.top"></a>
</nav>
</div>
</footer>
""" + tags + """
</body>
</html>
"""


# The date of this version of the privacy policy: the "Effective date" of docs/appstore/PRIVACY.md on main.
# Change it here when the policy text changes, and run this script again.
POLICY_DATE = "2026-10-16"

RHMENU = (ROOT / "tools/rh-menu-output.txt").read_text(encoding="utf-8").rstrip("\n")
MENU = json.loads((ROOT / "tools/rh-menu-output.json").read_text(encoding="utf-8"))
PLANS = json.loads((ROOT / "tools/rh-run-output.json").read_text(encoding="utf-8"))

# The glyphs the Finder extension draws itself (IconProvider.dedicatedGlyphs on main), exported to assets/menu/.
# Every other icon (an app's own icon, a system symbol such as text.bubble) is shown as a plain tile.
GLYPHS = {"arrow.up.forward.app": "open-with", "ellipsis.circle": "more-agents", "doc.badge.plus": "new-file",
          "doc.on.doc": "copy-path", "magnifyingglass": "reveal", "terminal": "terminal",
          "chevron.left.forwardslash.chevron.right": "editor"}


def menu_titles(nodes):
    for n in nodes:
        if n["kind"] != "separator":
            yield n["title"]
        yield from menu_titles(n["children"])


def text_titles(text):
    for line in text.splitlines()[1:]:
        line = line.strip()
        if line and set(line) != {"-"}:
            yield re.sub(r"\s{2,}\([^()]*\)$", "", line).removesuffix(" >")


def menu_actions(nodes):
    for n in nodes:
        if n.get("actionID"):
            yield n["actionID"]
        yield from menu_actions(n["children"])


assert list(menu_titles(MENU)) == list(text_titles(RHMENU)), "tools/rh-menu-output.json and .txt are not the same menu"
assert sorted(menu_actions(MENU)) == sorted(PLANS), "tools/rh-run-output.json does not cover exactly the actions of the menu"

# The explanation of an action: one sentence for each kind of action (home.try.k.<kind>), not one for each action.
KINDS = ["terminal", "app", "agent", "continue", "resume", "desktop", "link", "otherterminal", "preset", "newfile", "copy"]


def kind_of(action):
    if action.startswith("open.terminal"):
        return "terminal"
    if action.startswith(("open.editor", "open.app.")):
        return "app"
    if action.startswith("preset."):
        return "preset"
    if action.startswith("new-file."):
        return "newfile"
    if action.startswith("copy-path."):
        return "copy"
    if action.startswith("agent."):
        base, _, launcher = action.partition("@")
        if launcher in ("desktop", "link"):
            return launcher
        if launcher:
            return "otherterminal"
        if base.endswith((".continue", ".last")):
            return "continue"
        if base.endswith(".resume"):
            return "resume"
        return "agent"
    raise SystemExit(f"no kind of explanation for the action {action}")


# What the panel shows of a plan: the step that says the most, and the label for it (home.try.l.<detail>).
DETAILS = ["types", "opens", "url", "copies", "file"]


def detail_of(action):
    for step in PLANS[action]["steps"]:
        if step.get("types"):
            return "types", step["types"]
        if step.get("copies"):
            return "copies", step["copies"]
        if step.get("url"):
            return "url", step["url"]
        if step.get("file") and step["kind"] == "createFile":
            return "file", step["file"]
        if step.get("opens"):
            return "opens", ", ".join(step["opens"])
    return "", ""


# The state that the page starts in, also without JavaScript: the action of the hero chosen, and no submenu open.
OPEN_CHAIN = []
CHOSEN = "agent.claude"
SELECTED_FILE = "main.swift"

ROW, SEPARATOR, PAD = 24, 9, 6  # px: one row, one separator, a menu box's padding and border (see .try-menu in site.css)


def menu_height():
    """How tall the menu can get, in px: the bottom of the lowest submenu that a visitor can open. Submenus are positioned
    absolutely, so the box is told, and it keeps that height, so the page does not move when one opens."""
    def height(nodes):
        return sum(SEPARATOR if n["kind"] == "separator" else ROW for n in nodes)

    def lowest(nodes, top):
        bottom = top + height(nodes) + 2 * PAD
        for index, node in enumerate(nodes):
            if node["kind"] == "submenu":
                # a submenu's box starts level with its row, less its own padding
                bottom = max(bottom, lowest(node["children"], top + height(nodes[:index])))
        return bottom

    return lowest(MENU, 0) + 8


def app_names(nodes, found=None):
    """The name of each app of the menu, by bundle identifier: "Open in Ghostty" and "Claude Code Here" name theirs, an
    item of Open With is one."""
    found = {} if found is None else found
    for node in nodes:
        icon = node.get("icon") or {}
        if icon.get("kind") == "app" and icon.get("value") not in found:
            title = node["title"]
            name = title.removeprefix("Open in ").removesuffix(" Here")
            found[icon["value"]] = name
        app_names(node["children"], found)
    return found


APP_NAMES = app_names(MENU)


def icon_html(node):
    """A glyph that the Finder extension draws itself, or a tile: an app's own icon cannot be shown here, so its tile
    has the first letter of its name (it must not read as a check box), and a kind of file its extension."""
    icon = node.get("icon") or {}
    glyph = GLYPHS.get(icon.get("value")) if icon.get("kind") == "symbol" else None
    if glyph:
        return f'<img class="m-ico" src="assets/menu/{glyph}.png" width="16" height="16" alt="">'
    if icon.get("kind") == "app":
        label = APP_NAMES.get(icon.get("value"), node["title"])[:1].upper()
    elif icon.get("kind") == "fileType":
        label = str(icon.get("value", ""))[:2].upper()
    else:
        label = ""
    return f'<span class="m-ico plain{" wide" if len(label) > 1 else ""}" aria-hidden="true">{html.escape(label, quote=False)}</span>'


SUBMENU_IDS = iter(range(1, 100))


def menu_node(node, chain):
    """One menu row. `chain` is the part of OPEN_CHAIN that is still to open below this level."""
    if node["kind"] == "separator":
        return '<li class="m-sep" role="presentation"></li>'
    title = html.escape(node["title"], quote=False)
    if node["kind"] != "submenu":
        action = node["actionID"]
        detail, text = detail_of(action)
        attrs = (f'data-action="{html.escape(action)}" data-kind="{kind_of(action)}" '
                 f'data-summary="{html.escape(PLANS[action]["summary"])}" data-detail="{detail}" data-text="{html.escape(text)}"')
        pressed = "true" if action == CHOSEN else "false"
        return (f'<li class="m-item"><button type="button" class="m-row" {attrs} aria-pressed="{pressed}">'
                f'{icon_html(node)}<span class="m-title">{title}</span></button></li>')
    opened = bool(chain) and chain[0] == node["title"]
    sub_id = f"m-sub-{next(SUBMENU_IDS)}"
    rows = "".join(menu_node(c, chain[1:] if opened else []) for c in node["children"])
    return (f'<li class="m-item{" m-open" if opened else ""}"><button type="button" class="m-row" aria-expanded="{"true" if opened else "false"}" '
            f'aria-controls="{sub_id}">{icon_html(node)}<span class="m-title">{title}</span>'
            f'<span class="m-chev" aria-hidden="true">&#x203A;</span></button>'
            f'<ul class="m-sub" id="{sub_id}"{"" if opened else " hidden"}>{rows}</ul></li>')


def find(nodes, action):
    for n in nodes:
        if n.get("actionID") == action:
            return n
        found = find(n["children"], action)
        if found:
            return found
    return None


def try_section():
    rows = "\n".join(menu_node(n, OPEN_CHAIN) for n in MENU)
    chosen = find(MENU, CHOSEN)
    detail, text = detail_of(CHOSEN)
    kinds = "\n".join(
        f'<p class="try-kind" data-kind="{k}" data-i18n="home.try.k.{k}"{"" if k == kind_of(CHOSEN) else " hidden"}></p>' for k in KINDS)
    labels = "".join(
        f'<span class="try-detail-label" data-detail="{d}" data-i18n="home.try.l.{d}"{"" if d == detail else " hidden"}></span>' for d in DETAILS)
    return f"""<section class="block" id="try" aria-labelledby="try-h">
<div class="wrap">
<h2 id="try-h" data-i18n="home.try.title"></h2>
<p class="section-lead" data-i18n="home.try.lead"></p>
<div class="try">
<div class="try-menu" role="group" data-i18n-aria-label="home.try.label" lang="en" dir="ltr" style="--tall: {menu_height()}px">
<div class="fmenu"><ul class="m-list">
{rows}
</ul></div>
</div>
<div class="try-panel" id="try-panel">
<h3 class="try-kicker" data-i18n="home.try.does"></h3>
<p class="try-title" lang="en" dir="ltr" aria-live="polite">{html.escape(chosen["title"], quote=False)}</p>
{kinds}
<p class="try-label" data-i18n="home.try.command"></p>
<pre class="try-command"><code>rh run {html.escape(CHOSEN)} {SELECTED_FILE}</code></pre>
<p class="try-label" data-i18n="home.try.plan"></p>
<div class="try-plan">
<p class="try-summary" lang="en" dir="ltr">{html.escape(PLANS[CHOSEN]["summary"], quote=False)}</p>
<p class="try-detail">{labels} <code class="try-text">{html.escape(text, quote=False)}</code></p>
</div>
</div>
</div>
<p class="note" data-i18n="home.try.note2"></p>
<details class="raw">
<summary data-i18n="home.try.raw"></summary>
<pre lang="en" dir="ltr"><code>{html.escape(RHMENU, quote=False)}</code></pre>
</details>
</div>
</section>
"""


def node(title_key=None, sub_key=None, code=None, cls="node"):
    title = f'<code class="node-title">{code}</code>' if code else f'<span class="node-title" data-i18n="{title_key}"></span>'
    sub = f'<span class="node-sub" data-i18n="{sub_key}"></span>' if sub_key else ""
    return f'<div class="{cls}">{title}{sub}</div>'


def links(count):
    return '<div class="flow-links" aria-hidden="true">' + "".join(
        f'<span class="flow-link" style="--i: {i}"></span>' for i in range(count)) + "</div>"


FLOW = f"""<div class="flow" role="group" data-i18n-aria-label="home.how.diagram">
<div class="flow-col">
{node("home.how.finder", "home.how.finder.sub")}
{node("home.how.shell", "home.how.shell.sub")}
{node("home.how.ai", "home.how.ai.sub")}
</div>
{links(3)}
<div class="node node-hub"><code class="node-title">rh</code><span class="node-sub" data-i18n="home.how.rh.sub"></span>
<span class="hub-config"><code>config.toml</code><span data-i18n="home.how.config.sub"></span></span></div>
{links(3)}
<div class="flow-col">
{node("home.how.terminal")}
{node("home.how.editor")}
{node("home.how.agent")}
</div>
</div>"""


def tile(name, glyph, title="title", body="body"):
    return (f'<article class="tile"><img class="tile-ico" src="assets/menu/{glyph}.png" width="16" height="16" alt="">'
            f'<h3 data-i18n="home.what.{name}.{title}"></h3><p data-i18n="home.what.{name}.{body}"></p></article>')


INDEX = f"""<main id="main">
<section class="hero">
<div class="wrap">
<div>
<ul class="chips">
<li data-i18n="hero.chip.open"></li>
<li data-i18n="hero.chip.macos"></li>
<li data-i18n="hero.chip.silicon"></li>
<li data-i18n="hero.chip.license"></li>
</ul>
<h1 data-i18n="home.hero.title"></h1>
<p class="lead" data-i18n="home.hero.lead2"></p>
<div class="actions">
<a class="btn primary" href="https://github.com/boyugou/right-here/releases/latest" rel="noopener" data-i18n="home.hero.download"></a>
<a class="btn secondary" href="#try" data-i18n="home.hero.try"></a>
<a class="btn secondary" href="docs.html" data-keep-lang data-i18n="home.hero.docs"></a>
</div>
</div>
<figure class="shot demo">
<picture>
<source media="(prefers-reduced-motion: reduce)" srcset="assets/demo-static.svg">
<img src="assets/demo.svg" width="760" height="430" data-i18n-alt="home.hero.demo.alt">
</picture>
<figcaption data-i18n="home.hero.demo.caption"></figcaption>
</figure>
</div>
</section>

<section class="block" id="what" aria-labelledby="what-h">
<div class="wrap">
<h2 id="what-h" data-i18n="home.what.title"></h2>
<p class="section-lead" data-i18n="home.what.lead"></p>
<div class="tiles">
{tile("terminal", "terminal", body="body2")}
{tile("editor", "editor")}
{tile("agent", "more-agents", body="body2")}
{tile("preset", "more-agents", title="title2", body="body2")}
{tile("newfile", "new-file", body="body2")}
{tile("copy", "copy-path", body="body2")}
</div>
<p class="plain-note" data-i18n="home.what.quick2"></p>
</div>
</section>

__TRY__
<section class="block" id="setup" aria-labelledby="setup-h">
<div class="wrap">
<h2 id="setup-h" data-i18n="home.setup.title2"></h2>
<p class="section-lead" data-i18n="home.setup.lead"></p>
<ol class="steps">
<li><h3 data-i18n="home.setup.s0.title"></h3><p data-i18n="home.setup.s0.body"></p></li>
<li><h3 data-i18n="home.setup.s1.title"></h3><p data-i18n="home.setup.s1.body"></p></li>
<li><h3 data-i18n="home.setup.s2.title"></h3><p data-i18n="home.setup.s2.body"></p></li>
<li><h3 data-i18n="home.setup.s3.title"></h3><p data-i18n="home.setup.s3.body"></p></li>
</ol>
<p class="plain-note allow" data-i18n="home.setup.allow"></p>
<figure class="shots">
<div class="stack">
<picture>
<source media="(prefers-color-scheme: dark)" srcset="assets/setup-first-dark.png">
<img src="assets/setup-first-light.png" width="800" height="522" loading="lazy" data-i18n-alt="home.setup.first.alt">
</picture>
<picture>
<source media="(prefers-color-scheme: dark)" srcset="assets/setup-done-dark.png">
<img src="assets/setup-done-light.png" width="800" height="892" loading="lazy" data-i18n-alt="home.setup.done.alt">
</picture>
</div>
<figcaption data-i18n="home.setup.caption"></figcaption>
</figure>
<div class="grid two">
<article class="card"><h3 data-i18n="home.setup.cli.title"></h3><p data-i18n="home.setup.cli.body2"></p>
<pre><code>rh setup --dry-run
rh setup</code></pre></article>
<article class="card"><h3 data-i18n="home.setup.ai.title"></h3><p data-i18n="home.setup.ai.body"></p>
<pre><code>rh docs agent-setup</code></pre></article>
</div>
<p class="more-link"><a href="docs.html#install" data-keep-lang data-i18n="home.setup.link"></a></p>
</div>
</section>

<section class="block" id="status" aria-labelledby="status-h">
<div class="wrap">
<h2 id="status-h" data-i18n="home.status.title"></h2>
<p class="section-lead" data-i18n="home.status.lead3"></p>
<div class="status">
<div class="status-col done"><h3 data-i18n="home.status.auto.title"></h3><ul>
<li data-i18n="home.status.auto.1b"></li><li data-i18n="home.status.auto.2"></li></ul></div>
<div class="status-col done"><h3 data-i18n="home.status.real.title"></h3><ul>
<li data-i18n="home.status.real.1"></li><li data-i18n="home.status.real.2"></li></ul></div>
<div class="status-col open"><h3 data-i18n="home.status.open.title"></h3><ul>
<li data-i18n="home.status.open.1"></li><li data-i18n="home.status.open.2"></li><li data-i18n="home.status.open.3b"></li><li data-i18n="home.status.open.4"></li></ul></div>
<div class="status-col next"><h3 data-i18n="home.status.next.title"></h3><ul>
<li data-i18n="home.status.next.1c"></li><li data-i18n="home.status.next.2"></li><li data-i18n="home.status.next.3"></li></ul></div>
</div>
</div>
</section>

<section class="block" id="how" aria-labelledby="how-h">
<div class="wrap">
<h2 id="how-h" data-i18n="home.how.title"></h2>
<p class="section-lead" data-i18n="home.how.lead"></p>
{FLOW}
<ul class="points">
<li data-i18n="home.how.p1"></li>
<li data-i18n="home.how.p2b"></li>
<li data-i18n="home.how.p3"></li>
</ul>
</div>
</section>



<section class="block" id="ai" aria-labelledby="ai-h">
<div class="wrap">
<h2 id="ai-h" data-i18n="home.ai.title"></h2>
<p class="section-lead" data-i18n="home.ai.lead2"></p>
<div class="grid">
<article class="card"><h3 data-i18n="home.ai.mcp.title"></h3><p data-i18n="home.ai.mcp.body"></p>
<pre><code>claude mcp add right-here -- rh mcp</code></pre></article>
<article class="card"><h3 data-i18n="home.ai.plugin.title"></h3><p data-i18n="home.ai.plugin.body"></p>
<pre><code>/plugin marketplace add boyugou/right-here
/plugin install right-here@right-here</code></pre></article>
<article class="card"><h3 data-i18n="home.ai.playbook.title2"></h3><p data-i18n="home.ai.playbook.body"></p></article>
</div>
<div class="approve">
<h3 data-i18n="home.ai.flow.title"></h3>
<p data-i18n="home.ai.flow.lead"></p>
<ol class="chain">
<li data-i18n="home.ai.flow.1"></li>
<li data-i18n="home.ai.flow.2"></li>
<li data-i18n="home.ai.flow.3"></li>
</ol>
</div>
<p class="plain-note" data-i18n="home.ai.data2"></p>
</div>
</section>

<section class="block" id="safety" aria-labelledby="safety-h">
<div class="wrap">
<h2 id="safety-h" data-i18n="home.safety.title"></h2>
<p class="section-lead" data-i18n="home.safety.lead"></p>
<div class="grid">
<article class="card"><h3 data-i18n="home.safety.1.title"></h3><p data-i18n="home.safety.1.body"></p></article>
<article class="card"><h3 data-i18n="home.safety.2.title"></h3><p data-i18n="home.safety.2.body"></p></article>
<article class="card"><h3 data-i18n="home.safety.3.title2"></h3><p data-i18n="home.safety.3.body2"></p></article>
<article class="card"><h3 data-i18n="home.safety.4.title"></h3><p data-i18n="home.safety.4.body"></p></article>
<article class="card"><h3 data-i18n="home.safety.5.title"></h3><p data-i18n="home.safety.5.body"></p></article>
<article class="card"><h3 data-i18n="home.safety.6.title2"></h3><p data-i18n="home.safety.6.body2"></p></article>
</div>
</div>
</section>

<section class="block" id="languages" aria-labelledby="languages-h">
<div class="wrap">
<div class="cols">
<div>
<h2 id="languages-h" data-i18n="home.langs.title"></h2>
<p data-i18n="home.langs.body2"></p>
</div>
<figure class="shot">
<picture>
<source media="(prefers-color-scheme: dark)" srcset="assets/setup-ja-dark.png">
<img src="assets/setup-ja-light.png" width="800" height="521" loading="lazy" data-i18n-alt="home.langs.alt">
</picture>
<figcaption data-i18n="home.langs.caption"></figcaption>
</figure>
</div>
</div>
</section>


<section class="block cta" aria-labelledby="cta-h">
<div class="wrap">
<h2 id="cta-h" data-i18n="home.end.title"></h2>
<p class="section-lead" data-i18n="home.end.body"></p>
<div class="actions">
<a class="btn primary" href="docs.html" data-keep-lang data-i18n="home.end.docs"></a>
<a class="btn secondary" href="docs.html#troubleshooting" data-keep-lang data-i18n="home.end.trouble"></a>
</div>
</div>
</section>
</main>
"""


TOML = """[general]
terminal = "ghostty"
terminal_placement = "tab"           # a new tab in the front Ghostty window
editor = "vscode"
agents = ["claude", "codex", "lazygit"]   # what the menu offers, in order

[menu]                               # this is the default
items = ["open-terminal", "open-editor", "open-with", "agents", "agents-more", "-", "new-file", "copy-path"]

[new_file]
then = "open"

[[new_file.template]]
id = "md"
title = "Markdown Document"
extension = "md"
open_with = "typora"

[agent.claude]
command = "claude --model opus"      # what is typed into the shell

[agent.lazygit]                      # any command works like an agent
name = "lazygit"
command = "lazygit\""""

LAUNCHER_TOML = """[agent.claude]
launcher = "desktop"      # the agent's main menu entry opens the desktop app on the folder

[agent.codex]
launcher = "terminal"     # the default: the command is typed into a terminal"""

PRESET_TOML = """[[preset]]
id = "lint"
title = "Check Style"
agent = "claude"          # optional: the first agent in general.agents when left out
prompt = "Check {files} for style problems. Do not modify any files."
max_files = 10            # optional: 1 to 50, default 20

[agent.mytool]            # another agent: how its command takes a first prompt
name = "My Tool"
command = "mytool"
prompt_arg = "--prompt"   # or "positional\""""

OVERLAY_TOML = """# config.local.toml: this Mac has no Codex and uses another default terminal
disabled = ["codex"]

[general]
terminal = "terminal\""""

SYNC_USE = """rh config sync enable                     # choose the folder (default: iCloud Drive, folder "Right Here")
rh config sync enable --folder ~/Sync/rh  # any folder works: Dropbox, a git checkout, a network share
rh config sync push                       # send this Mac's config to the folder
rh config sync pull                       # take the folder's config (refused, with a list, if it adds programs)
rh config sync pull --allow-commands      # take it although it adds or changes terminal templates or agent commands
rh config sync status                     # in-sync, local-ahead, remote-ahead, diverged, remote-missing or remote-evicted
rh config sync disable                    # forget the folder; both copies stay"""

ALACRITTY_TOML = """[[app]]
id = "alacritty"
name = "Alacritty"
bundle_id = "org.alacritty"
role = "terminal"
open_args = ["/usr/bin/open", "-n", "-b", "org.alacritty", "--args", "--working-directory", "{dir}"]
run_args = ["/usr/bin/open", "-n", "-b", "org.alacritty", "--args", "--working-directory", "{dir}", "-e", "{shell}", "-lic", "{command}; exec {shell} -l"]"""

SETUP_USE = """rh setup                      # set everything up
rh setup --terminal ghostty --editor zed --agents claude,codex
rh setup --dry-run            # show what it would do, and change nothing
rh setup --json               # the report, for a script or an AI assistant"""

USE = """rh menu                       # the Finder menu for this folder
rh actions                    # the actions that you can run here
rh run agent.claude           # start Claude Code in this folder, in your terminal
rh run agent.claude --worktree   # the same, in a new git worktree of the repository
rh worktree list              # the worktrees (remove takes only the ones that Right Here made)
rh run copy-path.git-relative src/main.swift
rh run new-file.md --container ~/notes
rh pin ~/code/app             # pin a folder (rh pins and rh recents list them)
rh doctor                     # check the setup
rh doctor --probe-launch      # test a click: a terminal window opens and closes
rh config sync status         # compare this Mac's config with the sync folder"""

def items(*keys, tag="ul", cls=""):
    attr = f' class="{cls}"' if cls else ""
    return f"<{tag}{attr}>\n" + "\n".join(f'<li data-i18n="{k}"></li>' for k in keys) + f"\n</{tag}>"


def trouble(title_key, *body_keys):
    """One troubleshooting entry: a heading, then one paragraph or a list of the things to try."""
    if len(body_keys) == 1:
        return f'<h3 data-i18n="{title_key}"></h3>\n<p data-i18n="{body_keys[0]}"></p>\n'
    return f'<h3 data-i18n="{title_key}"></h3>\n{items(*body_keys)}\n'


# The order of docs/TROUBLESHOOTING.md on main, shortened to what most people meet.
TROUBLE = "".join([
    trouble("doc.t1.title", "doc.t1.a", "doc.t1.b", "doc.t1.c", "doc.t1.d", "doc.t1.e"),
    trouble("d.t2.title", "doc.t2.a", "doc.t2.b", "doc.t2.c"),
    trouble("d.t3.title", "doc.t3.body"),
    trouble("d.t4.title", "doc.t4.body"),
    trouble("d.t5.title", "doc.t5.a", "doc.t5.b", "doc.t5.c"),
    trouble("d.t6.title", "doc.t6.body"),
    trouble("d.t7.title", "doc.t7.body2"),
    trouble("d.t8.title", "doc.t8.body"),
    '<h3 data-i18n="doc.t10.title"></h3>\n<p data-i18n="doc.t10.body"></p>\n'
    + items("doc.t10.a", "doc.t10.b", "doc.t10.c", "doc.t10.d") + "\n",
    trouble("doc.t9.title", "doc.t9.body"),
])

DOCS = f"""<main id="main" class="wrap docs">
<nav class="toc" data-i18n-aria-label="docs.toc">
<h2 data-i18n="docs.toc"></h2>
<ol>
<li><a href="#install" data-i18n="doc.install.title"></a></li>
<li><a href="#setup" data-i18n="doc.setup.title"></a></li>
<li><a href="#use" data-i18n="doc.use.title"></a></li>
<li><a href="#actions" data-i18n="d.actions.title"></a></li>
<li><a href="#config" data-i18n="d.config.title"></a></li>
<li><a href="#presets" data-i18n="d.presets.title"></a></li>
<li><a href="#shortcuts" data-i18n="d.shortcuts.title"></a></li>
<li><a href="#sync" data-i18n="doc.sync.title"></a></li>
<li><a href="#terminals" data-i18n="d.terminals.title"></a></li>
<li><a href="#mcp" data-i18n="doc.mcp.title"></a></li>
<li><a href="#troubleshooting" data-i18n="d.trouble.title"></a></li>
</ol>
</nav>
<div class="doc-body">
<h1 data-i18n="docs.title"></h1>
<p class="lead" data-i18n="doc.lead"></p>
<p class="banner" data-i18n="doc.status3"></p>
<p><a href="index.html" data-keep-lang data-i18n="docs.home"></a></p>

<section id="install" aria-labelledby="install-h">
<h2 id="install-h" data-i18n="doc.install.title"></h2>
{items("doc.install.1b", "doc.install.2", "doc.install.3", tag="ol", cls="numbered")}
<p data-i18n="doc.install.brew"></p>
<pre><code>brew install --cask boyugou/tap/right-here</code></pre>
<p data-i18n="doc.install.move"></p>
<p data-i18n="doc.install.update2"></p>
<p data-i18n="doc.install.source2"></p>
<pre><code>brew install xcodegen
./script/install_local.sh     # builds the app, copies it to ~/Applications and runs rh setup</code></pre>
</section>

<section id="setup" aria-labelledby="setup-h">
<h2 id="setup-h" data-i18n="doc.setup.title"></h2>
<p data-i18n="doc.setup.p1"></p>
{items("doc.setup.way1", "doc.setup.way2", "doc.setup.way3")}
<p data-i18n="doc.setup.order"></p>
{items("doc.setup.s1", "doc.setup.s2", "doc.setup.s3", "doc.setup.s4", "doc.setup.s5", "doc.setup.s6", tag="ol", cls="numbered")}
<pre><code>{SETUP_USE}</code></pre>
<p data-i18n="doc.setup.again"></p>
<p data-i18n="doc.setup.config"></p>
<p data-i18n="doc.setup.you"></p>
{items("doc.setup.you1", "doc.setup.you2", "doc.setup.you3")}
<h3 id="first-run" data-i18n="doc.first.title"></h3>
<p data-i18n="doc.first.p1"></p>
<p data-i18n="doc.first.p2"></p>
<p data-i18n="doc.first.p3"></p>
<p data-i18n="doc.first.p4"></p>
<p class="beta" data-i18n="doc.first.beta"></p>
<h3 id="ai-setup" data-i18n="doc.ai.title"></h3>
<p data-i18n="doc.ai.p1"></p>
<p data-i18n="doc.ai.steps"></p>
{items("doc.ai.s1", "doc.ai.s2", "doc.ai.s3", "doc.ai.s4", "doc.ai.s5", "doc.ai.s6", tag="ol", cls="numbered")}
<p data-i18n="doc.ai.never"></p>
<p data-i18n="doc.ai.tested2"></p>
</section>

<section id="use" aria-labelledby="use-h">
<h2 id="use-h" data-i18n="doc.use.title"></h2>
<p data-i18n="doc.use.p1"></p>
<pre><code>{USE}</code></pre>
<p data-i18n="doc.use.icloud"></p>
<p data-i18n="doc.use.preview"></p>
<p data-i18n="doc.use.completion"></p>
</section>

<section id="actions" aria-labelledby="actions-h">
<h2 id="actions-h" data-i18n="d.actions.title"></h2>
<p data-i18n="doc.actions.p1"></p>
<div class="tablewrap">
<table>
<thead><tr><th scope="col" data-i18n="d.actions.col.id"></th><th scope="col" data-i18n="d.actions.col.does"></th></tr></thead>
<tbody>
<tr><td><code>open.terminal</code></td><td data-i18n="doc.actions.terminal"></td></tr>
<tr><td><code>open.editor</code></td><td data-i18n="doc.actions.editor"></td></tr>
<tr><td><code>open.app.&lt;app&gt;</code></td><td data-i18n="doc.actions.app"></td></tr>
<tr><td><code>agent.claude</code></td><td data-i18n="doc.actions.agent"></td></tr>
<tr><td><code>preset.review</code></td><td data-i18n="doc.actions.preset"></td></tr>
<tr><td><code>copy-path.git-relative</code></td><td data-i18n="doc.actions.copy"></td></tr>
<tr><td><code>new-file.md</code></td><td data-i18n="doc.actions.newfile"></td></tr>
<tr><td><code>reveal</code></td><td data-i18n="doc.actions.reveal"></td></tr>
<tr><td><code>repository.copy-link</code></td><td data-i18n="doc.actions.repoCopy"></td></tr>
<tr><td><code>repository.open-page</code></td><td data-i18n="doc.actions.repoOpen"></td></tr>
</tbody>
</table>
</div>
<p data-i18n="doc.actions.p2"></p>
<pre><code>rh run agent.claude --dry-run --json</code></pre>
</section>

<section id="config" aria-labelledby="config-h">
<h2 id="config-h" data-i18n="d.config.title"></h2>
<p data-i18n="doc.config.p1"></p>
<pre><code>{TOML}</code></pre>
<p data-i18n="doc.config.how"></p>
{items("doc.config.how1", "doc.config.how2", "doc.config.how3")}
<p data-i18n="doc.config.check"></p>
<p data-i18n="doc.config.bypass"></p>
<h3 id="launcher" data-i18n="d.agentapp.title"></h3>
<p data-i18n="doc.agentapp.p1"></p>
<p data-i18n="doc.agentapp.p2b"></p>
<pre><code>{LAUNCHER_TOML}</code></pre>
</section>

<section id="presets" aria-labelledby="presets-h">
<h2 id="presets-h" data-i18n="d.presets.title"></h2>
<p data-i18n="doc.presets.p1"></p>
<p data-i18n="doc.presets.p2"></p>
<p data-i18n="doc.presets.p3"></p>
<pre><code>{PRESET_TOML}</code></pre>
{items("doc.presets.v1", "doc.presets.v2", "doc.presets.v3")}
<p data-i18n="doc.presets.p5b"></p>
<p data-i18n="doc.presets.p6"></p>
<p data-i18n="doc.presets.p7"></p>
<p class="beta" data-i18n="doc.presets.beta"></p>
</section>

<section id="shortcuts" aria-labelledby="shortcuts-h">
<h2 id="shortcuts-h" data-i18n="d.shortcuts.title"></h2>
<p data-i18n="doc.shortcuts.p1"></p>
<p data-i18n="doc.shortcuts.p2b"></p>
<p data-i18n="doc.shortcuts.p3"></p>
<ul class="phrases" lang="en" dir="ltr">
<li>Open in terminal with Right Here</li>
<li>Start an agent with Right Here</li>
<li>Create a new file with Right Here</li>
<li>Copy a path with Right Here</li>
</ul>
<p class="beta" data-i18n="doc.shortcuts.beta"></p>
</section>

<section id="sync" aria-labelledby="sync-h">
<h2 id="sync-h" data-i18n="doc.sync.title"></h2>
<p data-i18n="doc.sync.p1"></p>
<h3 data-i18n="doc.sync.h1"></h3>
<p data-i18n="doc.sync.p2"></p>
{items("doc.sync.r1", "doc.sync.r2", "doc.sync.r3", "doc.sync.r4", "doc.sync.r5")}
<p data-i18n="doc.sync.example"></p>
<pre><code>{OVERLAY_TOML}</code></pre>
<h3 data-i18n="doc.sync.h2"></h3>
<p data-i18n="doc.sync.p3"></p>
<pre><code>{SYNC_USE}</code></pre>
<p data-i18n="doc.sync.p4"></p>
{items("doc.sync.rule1", "doc.sync.rule2", "doc.sync.rule3", "doc.sync.rule4")}
<h3 data-i18n="doc.sync.h3"></h3>
<p data-i18n="doc.sync.p8"></p>
{items("doc.sync.c1", "doc.sync.c2", "doc.sync.c3", "doc.sync.c4", "doc.sync.c5")}
<p data-i18n="doc.sync.p9"></p>
<p data-i18n="doc.sync.p6"></p>
<p class="beta" data-i18n="doc.sync.beta"></p>
</section>

<section id="terminals" aria-labelledby="terminals-h">
<h2 id="terminals-h" data-i18n="d.terminals.title"></h2>
<p data-i18n="doc.terminals.p1b"></p>
<div class="tablewrap">
<table>
<thead><tr><th scope="col" data-i18n="d.terminals.col.terminal"></th><th scope="col" data-i18n="d.terminals.col.notes"></th></tr></thead>
<tbody>
<tr><td>Ghostty</td><td data-i18n="doc.terminals.ghostty"></td></tr>
<tr><td>Terminal</td><td data-i18n="doc.terminals.terminal"></td></tr>
<tr><td>iTerm2</td><td data-i18n="doc.terminals.iterm"></td></tr>
<tr><td>WezTerm</td><td data-i18n="doc.terminals.wezterm"></td></tr>
<tr><td>kitty</td><td data-i18n="doc.terminals.kitty"></td></tr>
<tr><td>Alacritty</td><td data-i18n="doc.terminals.alacritty"></td></tr>
<tr><td>Warp</td><td data-i18n="doc.terminals.warp"></td></tr>
<tr><td>cmux</td><td data-i18n="doc.terminals.folderonly"></td></tr>
</tbody>
</table>
</div>
<p data-i18n="doc.terminals.p3"></p>
{items("doc.terminals.a1", "doc.terminals.a2", "doc.terminals.a3", "doc.terminals.a4")}
<p data-i18n="doc.terminals.p4"></p>
<pre><code>{ALACRITTY_TOML}</code></pre>
<p data-i18n="doc.terminals.p5"></p>
</section>

<section id="mcp" aria-labelledby="mcp-h">
<h2 id="mcp-h" data-i18n="doc.mcp.title"></h2>
<p data-i18n="doc.mcp.p0"></p>
<p data-i18n="doc.mcp.p1"></p>
<pre><code>claude mcp add right-here -- rh mcp</code></pre>
<p data-i18n="doc.mcp.p2"></p>
<p data-i18n="doc.mcp.p3"></p>
<pre><code>/plugin marketplace add boyugou/right-here
/plugin install right-here@right-here</code></pre>
<p data-i18n="doc.mcp.p4"></p>
<p data-i18n="doc.mcp.p5"></p>
<p data-i18n="doc.mcp.p6"></p>
</section>

<section id="troubleshooting" aria-labelledby="trouble-h">
<h2 id="trouble-h" data-i18n="d.trouble.title"></h2>
<p data-i18n="doc.trouble.p1"></p>
{items("doc.trouble.json", "doc.trouble.probe", "doc.trouble.report", "doc.trouble.lang2")}
{TROUBLE}</section>
</div>
</main>
"""

PRIVACY = f"""<main id="main" class="wrap docs privacy">
<div class="doc-body">
<h1 data-i18n="priv.title"></h1>
<p class="note"><span data-i18n="priv.effective"></span> <time datetime="{POLICY_DATE}">{POLICY_DATE}</time></p>
<p class="lead" data-i18n="priv.intro"></p>

<section aria-labelledby="p-collect"><h2 id="p-collect" data-i18n="priv.collect.title"></h2>
<p data-i18n="priv.collect.body"></p></section>

<section aria-labelledby="p-reads"><h2 id="p-reads" data-i18n="priv.reads.title"></h2>
<ul>
<li data-i18n="priv.reads.1"></li>
<li data-i18n="priv.reads.2"></li>
<li data-i18n="priv.reads.3"></li>
</ul>
<p data-i18n="priv.reads.note"></p></section>

<section aria-labelledby="p-stores"><h2 id="p-stores" data-i18n="priv.stores.title"></h2>
<ul>
<li data-i18n="priv.stores.1"></li>
<li data-i18n="priv.stores.sync"></li>
<li data-i18n="priv.stores.folders"></li>
<li data-i18n="priv.stores.2"></li>
</ul></section>

<section aria-labelledby="p-events"><h2 id="p-events" data-i18n="priv.events.title"></h2>
<p data-i18n="priv.events.body"></p></section>

<section aria-labelledby="p-other"><h2 id="p-other" data-i18n="priv.other.title"></h2>
<p data-i18n="priv.other.body"></p></section>

<section aria-labelledby="p-children"><h2 id="p-children" data-i18n="priv.children.title"></h2>
<p data-i18n="priv.children.body"></p></section>

<section aria-labelledby="p-open"><h2 id="p-open" data-i18n="priv.open.title"></h2>
<p data-i18n="priv.open.body"></p>
<p><a href="https://github.com/boyugou/right-here" rel="noopener">github.com/boyugou/right-here</a></p></section>

<section aria-labelledby="p-changes"><h2 id="p-changes" data-i18n="priv.changes.title"></h2>
<p data-i18n="priv.changes.body"></p>
<p><span data-i18n="priv.changes.contact"></span> <a href="https://github.com/boyugou/right-here/issues" rel="noopener" data-i18n="priv.changes.link"></a></p></section>

<p><a href="index.html" data-keep-lang data-i18n="docs.home"></a></p>
</div>
</main>
"""


# The demo in the hero is one SVG with its own animation. A browser does not pass "reduce motion" into an SVG that a page
# shows as an image, so the page picks assets/demo-static.svg for that: the same file with its animation switched off,
# which shows the end of the story (the menu with Claude Code Here chosen, and the command typed in the terminal).
DEMO = (ROOT / "assets/demo.svg").read_text(encoding="utf-8")
REDUCED = "  @media (prefers-reduced-motion: reduce) {\n    .cursor, .pick, .menu, .hover, .term, .typed, .caret { animation: none; }\n  }\n"
assert REDUCED in DEMO, "assets/demo.svg no longer has the rule that stops its animation"
(ROOT / "assets/demo-static.svg").write_text(
    DEMO.replace(REDUCED, "  .cursor, .pick, .menu, .hover, .term, .typed, .caret { animation: none; }\n"), encoding="utf-8")

for name, tk, dk, body, scripts in [
    ("index.html", "meta.home.title", "meta.home.description2", INDEX, ("site.js", "menu.js")),
    ("docs.html", "meta.docs.title", "meta.docs.description2", DOCS, ("site.js",)),
    ("privacy.html", "meta.privacy.title", "meta.privacy.description", PRIVACY, ("site.js",)),
]:
    body = body.replace("__TRY__", try_section())
    page = head(name, tk, dk) + header() + body + footer(scripts)
    page, used = fill(page)
    (ROOT / name).write_text(page, encoding="utf-8")
    print(name, len(used), "keys")
