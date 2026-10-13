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
  `Apps/RightHere/icon-1024.png` and `script/preview_setup.sh` on `main`). Render the window with `--demo` (add
  `--details` for the list of checks, `--onboarding` for the first-run card): it shows canned checks, the same on every
  Mac, with no path, last action, agent or terminal of the Mac that renders it. Without `--demo` the window shows that
  Mac's own checks.

The translations of the site were machine-generated and are marked for native-speaker review, like the app's.
