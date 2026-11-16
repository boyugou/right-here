# 0033: A current-directory identity and a quieter setup window

Date: 2026-11-15. Status: implemented; aesthetic approval remains open. Supersedes [0031](0031-app-icon-geometry.md).

## Problem and process

The luminous target icon had too many competing effects. Its replacement, a folder with an arrow, removed those effects but
still lacked a distinct idea. The user rejected both directions and asked for a dedicated design review. That review examined
the product, compared original concepts at actual icon sizes, and then reviewed the implementation in the app's SwiftUI views.

Right Here turns a location already selected in Finder into the starting point of an action. The window supports setup,
verification and a few saved locations. It should not look like a dashboard whose every feature needs its own promotional card.

## Identity

The mark comes from `./`, the current-directory prefix. It is drawn as two custom shapes, not rendered from a font. A substantial
ivory slash and a moss-colored origin sit on a forest-green tile. The point and slash share a baseline; the point has separate
optical corrections at 16 and 32 pixels. A continuous tile contour and rounded joins avoid abrupt corners. No glow, metallic
frame, baked glass or simulated reflection is part of the artwork.

Three earlier concepts were rejected: an arrow leaving a corner looked like the system's external-link command, a folded folder
remained generic, and an initial plus an arrow needed too much explanation. A second folded initial read as a different letter.
The blue version of the current-directory mark was legible but gave the identity less distinction. These comparisons informed
the choice; they do not establish trademark uniqueness or the user's approval.

The editable vectors are in [`Design/AppIcon`](../../Design/AppIcon/). `script/generate_app_icon.swift` draws every shipped
resolution independently and can produce a size-comparison sheet. The asset catalog still uses ordinary PNGs. Separate SVG
layers are retained as design sources, but there is no Icon Composer build: its first launch required an unaccepted license,
so that optional path was closed without accepting it. No system-generated icon material is claimed.

## Window

- A compact brand row replaces the permanent multiline pitch. Version moves to the foot of the sidebar. Existing pages are
  grouped by purpose: Overview / Finder menu / AI Assistants, Folders / Worktrees, then Checks. The Command-1 through Command-6
  mappings were initially retained; [0035](0035-navigation-order.md) subsequently aligns them and the View menu with these groups.
  The native title bar retains window controls without repeating the product name.
- A shared palette defines surfaces, separators and emphasis. Content keeps system text colors and fonts. Forest is the default
  accent asset; the native controls and custom selection marks resolve `Color.accentColor`, so the system's chosen accent can
  replace it. The scratch renderer has no asset catalog and uses the specified default color for its canned previews.
- The healthy Overview gives the readiness statement and its next action the strongest hierarchy. A bounded, labeled preview
  reads the actual menu tree; it shows up to five entries and preserves submenu indicators. The full preview remains one click
  away. The full preview explains that submenus expand here and actions run in Finder; only expandable rows receive hover and
  pressed feedback, with their text kept at normal contrast. Default apps use light information rows. First-run, incomplete
  setup and failed checks retain their own states.
- First-run choices use restrained rectangular controls with separate single- and multiple-choice marks. There is one prominent
  Set Up action and no enclosing colored card. Long descriptions and additional agent choices remain available.
- Folders and worktrees use a shared list container with inset separators. Names lead, paths are secondary, and actions remain
  visible with a full hit area. Quiet buttons retain their labels and disabled states and add hover/pressed feedback. Search,
  no-match, empty, read-failure and operation feedback remain distinct. No storage or worktree-removal rule changes.
- All existing localized copy is retained. Layout wraps instead of shrinking text, mirrors for right-to-left languages, and
  retains explicit left-to-right path rendering. Increased contrast strengthens surface boundaries.

## Reference principles

- [Apple's app-icon guidance](https://developer.apple.com/design/human-interface-guidelines/app-icons): a recognizable core
  shape must survive small sizes and different appearances. This informed the native-size comparisons and large foreground forms.
- [Pentagram's Slack identity case](https://www.pentagram.com/work/slack): find a visual idea in the product's own vocabulary,
  then examine its reproduction across contexts. Only the method informed this work; no artwork was reused.
- [Things' design discussion](https://culturedcode.com/things/features/): repeating content rows and progressive disclosure
  deserve the same attention as a brand mark. This informed the list rhythm and quieter secondary information.
- [Apple's sidebar guidance](https://developer.apple.com/design/human-interface-guidelines/sidebars) and
  [accent-color behavior](https://developer.apple.com/documentation/SwiftUI/Color/accentColor): navigation uses familiar symbols,
  short labels and the person's system accent choice. The asset-catalog accent supplies the default rather than forcing one tint.

## Verification

The design review compared two concept rounds, then inspected actual SwiftUI renders and requested another pass on first-run
spacing, default-app icon weight, the recent-list action and submenu indicators. English, Chinese, German, French, Russian and
Arabic renders exercise the minimum window, dark appearance and long text. ImageRenderer's large-text flag is not evidence of
macOS text scaling; see [0017](0017-setup-window-sections.md). Native controls need native verification in addition to these renders.

The icon generator is checked for the dimensions of all ten asset slots, transparency and deterministic regeneration. The app
and Finder extension build with strict Swift concurrency. Full repository checks and the native outcomes are recorded in the
manual checklist; the design changes do not change the protections in DESIGN section 9.
