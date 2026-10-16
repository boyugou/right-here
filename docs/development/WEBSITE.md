# The website

The public site lives on its own orphan branch, `gh-pages`, as plain static files (no build step, no external
fonts or scripts). It is served by GitHub Pages from that branch.

- Pages: landing, docs, privacy policy, 404. Thirty languages (the same list as the app), chosen from the browser's
  languages and remembered; right-to-left for Arabic, Persian, Hebrew and Urdu. English is written in the HTML and
  is the fallback for any missing string.
- Strings are in `i18n/<lang>.json`; `tools/check_i18n.py` verifies every language has exactly the English keys.
  `tools/check_site.py` checks links, ids, alt text and page weight. Both must pass before a push.
- To publish: in the repository settings choose Pages, source branch `gh-pages`, folder root. Then run
  `python3 tools/set_base_url.py https://<user>.github.io/right-here/` on the branch once so canonical, hreflang,
  Open Graph and the sitemap carry absolute URLs.
- To refresh the icon, social card and screenshots after the app changes: see the branch's README (they come from
  `Apps/RightHere/icon-1024.png` and `script/preview_setup.sh` on `main`). `uv run tools/make_icons.py` rewrites the icon
  files; the header icon is 128 px because it is shown at 32, and a bigger one pushes the pages over their weight budget.
  Render the window with `--demo`, `--first-run` or `--set-up` (never plain: without them it shows that Mac's own checks, folders
  and menu): they show canned data, the same on every Mac, with no path, last action, agent or terminal of the Mac that renders
  them, and the script stops when a canned text names that Mac's home folder or account.
- The screenshots to use, each light and dark (`--dark`), 860 points wide at 2x and resized to 800 px: `en --demo --tab menu` for
  the hero (the Finder menu section next to the sidebar of six sections; plain `--demo` is the Overview, which is mostly empty),
  `en --first-run` for the very first run (no config file, the choice of terminal, editor and agents), `en --set-up` for just after
  Set Up (what it did, and the Finder extension still to switch on) and `ja --demo --tab menu` for the translated window. The
  site draws its menu mock-up from `tools/rh-menu-output.json`, so `--submenus` is not used. The icons of the menu's apps
  (Ghostty, Visual Studio Code, Xcode, TextEdit, Terminal) come from the Mac that renders it, so render on one that has them: an
  app it lacks is drawn with the plain app icon. `--gallery` is for checking text, not for the site. The strings are in
  `i18n/en.json`; each key that is new or changed costs a translation in every other language, so prefer rewording one sentence to
  adding another.

The translations of the site were machine-generated and are marked for native-speaker review, like the app's.
