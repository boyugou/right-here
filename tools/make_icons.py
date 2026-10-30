# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow"]
# ///
"""Regenerates the icon-derived assets from the app icon.

    uv run tools/make_icons.py path/to/icon-1024.png

Writes assets/icon.png (128, shown at 32 so the page stays light), assets/favicon-32.png, assets/apple-touch-icon.png (180) and
assets/og-image.png (1200x630 social card). The site only ever references these files, so a new
icon is: run this once, commit.
"""
import pathlib
import sys

from PIL import Image, ImageDraw, ImageFont

ASSETS = pathlib.Path(__file__).resolve().parent.parent / "assets"
src = Image.open(sys.argv[1]).convert("RGBA")


def resized(px):
    return src.resize((px, px), Image.LANCZOS)


resized(128).save(ASSETS / "icon.png", optimize=True)
resized(32).save(ASSETS / "favicon-32.png", optimize=True)

touch = Image.new("RGBA", (180, 180), (255, 255, 255, 255))  # iOS rounds the corners itself
touch.alpha_composite(resized(180))
touch.convert("RGB").save(ASSETS / "apple-touch-icon.png", optimize=True)


def font(size, bold):
    for path, index in (("/System/Library/Fonts/Helvetica.ttc", 1 if bold else 0),
                        ("/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Arial.ttf", 0),
                        ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 0)):
        try:
            return ImageFont.truetype(path, size, index=index)
        except OSError:
            continue
    return ImageFont.load_default()


W, H = 1200, 630
card = Image.new("RGB", (W, H))
top, bottom = (36, 28, 96), (12, 10, 32)  # the icon's violet, darkened
px = card.load()
for y in range(H):
    t = y / (H - 1)
    row = tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
    for x in range(W):
        px[x, y] = row
card = card.convert("RGBA")
card.alpha_composite(resized(300), (110, 165))
d = ImageDraw.Draw(card)
d.text((470, 190), "Right Here", font=font(96, True), fill=(255, 255, 255))
d.text((474, 315), "Send a folder to your terminals,", font=font(38, False), fill=(206, 200, 240))
d.text((474, 365), "editors and AI agents.", font=font(38, False), fill=(206, 200, 240))
d.text((474, 450), "macOS 26+  ·  Apple silicon  ·  Apache-2.0  ·  open source", font=font(26, False), fill=(160, 150, 250))
card.convert("RGB").save(ASSETS / "og-image.png", optimize=True)
print("wrote icon.png, favicon-32.png, apple-touch-icon.png, og-image.png")
