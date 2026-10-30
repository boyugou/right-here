# The website

The public website is on its own orphan branch, `gh-pages`. It is plain static files: no build step, no external fonts
and no external scripts. GitHub Pages serves it from that branch.

## What it has

- Four pages: the home page, the documentation, the privacy policy and a 404 page.
- 30 languages, the same list as the app. The page picks a language from the browser and remembers the choice. Arabic,
  Persian, Hebrew and Urdu read from right to left. English is in the HTML, and it is the fallback for a missing string.
- On the home page: an animation of a right-click (`assets/demo.svg`), a menu that a visitor can try, and a diagram of
  how a click flows.

## Change the text

1. Edit `i18n/en.json`. Follow [`WRITING.md`](WRITING.md).
2. Give a new key to each sentence that you reword. Then `tools/check_i18n.py` asks for its translation in every
   language.
3. Run `python3 tools/render_pages.py`, then `python3 tools/set_base_url.py https://boyugou.github.io/right-here/`.
4. Translate the new keys in `i18n/<lang>.json`.
5. Run the checks. Both must pass.

Each new or changed key costs a translation in 29 languages. So reword one sentence rather than add another.

## The checks

- `tools/check_i18n.py`: each language has exactly the English keys and the same code spans, and its text is in that
  language.
- `tools/check_site.py`: links, ids, alt text, image sizes, page weight, and no path or account name of the Mac that
  built the site.

## The menu to try

`tools/capture_rh.py <path to rh>` records the menu and the plan of each action, from a throwaway home. Run it with a
build of `rh` from `main` when the menu or the plans change. The README of the branch has the details.

## The animation

`assets/demo.svg` is drawn by hand. `docs/images/demo.svg` and `docs/images/demo-static.svg` on `main` are copies for
the README. Change the copies together.

## The screenshots

Render the setup window with `script/preview_setup.sh` on `main`. Always use `--demo`, `--first-run` or `--set-up`.
Without them, the window shows the checks, folders and menu of the Mac that renders it. Each picture is light and dark
(`--dark`), 860 points wide at 2x, and resized to 800 px.

| Flags | Picture | Where |
| --- | --- | --- |
| `en --first-run` | the first run: no config file, the choice of terminal, editor and agents | site |
| `en --set-up` | just after Set Up: what it did, and the Finder extension still to turn on | site |
| `ja --demo --tab menu --default-window` | the Finder menu page in Japanese | site |
| `en --demo --tab menu --default-window` | the Finder menu page | README (`docs/images/setup-*.png`) |

In these pictures an app's or a document's icon is a plain tile drawn by the preview (a coloured square with the app's
initial, a page with the extension), never that app's own artwork, so the pictures look the same on any Mac.

`uv run tools/make_icons.py <path to docs/images/icon.png>` rewrites the icon files from the app's icon, which `uv run script/export_icon.py` draws from `Apps/RightHere/AppIcon.icon`.

## Publish

1. In the repository settings, choose Pages, source branch `gh-pages`, folder root.
2. Run `python3 tools/set_base_url.py https://<user>.github.io/right-here/` on the branch once. Then canonical,
   hreflang, Open Graph and the sitemap have absolute URLs.

Machines made the translations of the site, as for the app. They wait for review by native speakers.
