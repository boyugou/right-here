# 0031: The app icon uses a folder and one action mark

Date: 2026-11-15. Status: accepted.

## Problem

The icon combined a metallic frame, glass highlights, a luminous target, and a terminal prompt. Its generator cropped a JPEG
inside a second outer shape. The small icon lost the folder and action in its decorative detail, and the visual language felt
artificial rather than like a dependable Mac utility.

## Decision

Use a warm off-white tile, an ink-colored folder and one clay-colored turning arrow. The folder supplies the context; the arrow
supplies the action. Recognition comes from the silhouette, proportions and contrast. A small outer shadow separates the tile
from a light surface; the artwork has no lighting effects or decorative frame. The app's controls keep the system accent color.

`script/generate_app_icon.swift` owns the geometry, palette and exports. It draws each of the ten macOS icon slots directly at
its required resolution, with a slightly heavier mark at the smallest sizes, and also writes the README and preview image.
There is no raster master to crop or enlarge. Passing a preview directory renders size and palette comparisons on light and
dark surfaces. The editable source and generated icon assets stay together in the repository.

## Alternatives and review

An ink tile with a muted green folder and an off-white tile with a blue folder were rendered beside the selected palette.
The light tile retains a distinct outline on dark surfaces, and the ink folder retains contrast on light surfaces. Reworking the
original glossy artwork would retain its unnecessary complexity. A terminal-only mark would narrow the identity to one of
the app's destinations; a location target would keep the previous ambiguity with a tracking or network utility.

The comparison includes 16, 32, 64, 128 and 1024-pixel exports. All ten asset slots have their required dimensions and alpha;
the eleven PNG exports reproduce byte for byte. The app's own headless window renderer and a built app with a temporary home
both displayed the new icon. The full build, 1,738 tests, app and extension build, localization and repository checks passed.
The native Dock accessibility request timed out, so direct Dock inspection remains a manual check.
