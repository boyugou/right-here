# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow"]
# ///
"""Draws the app icon for the places that cannot read an Icon Composer document.

    uv run script/export_icon.py

The icon is Apps/RightHere/AppIcon.icon, which Xcode compiles into the app with its light, dark and tinted looks. The
README, the setup window's preview and the website show docs/images/icon.png instead: the light look, 1024 px, its body
824 px inside the margin of the macOS icon grid, the size the Dock and Finder give every icon. ictool, which draws it,
comes with Xcode's Icon Composer.
"""
import pathlib
import subprocess
import sys
import tempfile

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "Apps/RightHere/AppIcon.icon"
OUTPUT = ROOT / "docs/images/icon.png"
CANVAS, BODY = 1024, 824

developer = pathlib.Path(subprocess.run(["xcode-select", "-p"], capture_output=True, text=True, check=True).stdout.strip())
ictool = developer.parent / "Applications/Icon Composer.app/Contents/Executables/ictool"
if not ictool.exists():
    sys.exit(f"error: no ictool at {ictool}; select an Xcode 26 or later with xcode-select")

with tempfile.TemporaryDirectory() as scratch:
    body_png = pathlib.Path(scratch) / "body.png"
    subprocess.run([ictool, SOURCE, "--export-image", "--output-file", body_png, "--platform", "macOS",
                    "--rendition", "Default", "--width", str(BODY), "--height", str(BODY), "--scale", "1"],
                   capture_output=True, check=True)
    body = Image.open(body_png).convert("RGBA")
icon = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
icon.alpha_composite(body, ((CANVAS - BODY) // 2, (CANVAS - BODY) // 2))
icon.save(OUTPUT, optimize=True)
print(f"wrote {OUTPUT.relative_to(ROOT)}")
