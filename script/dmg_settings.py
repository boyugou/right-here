# The disk image's window, for dmgbuild (script/package_dmg.sh passes `app` and `icon` with -D). dmgbuild writes the
# window's layout into the image's .DS_Store itself; nothing asks Finder to arrange it.
#
# The app on the left and the Applications folder on the right, at the size Finder shows them, in a window without a
# toolbar or a sidebar. The ground is Finder's own, so the names stay readable in light and dark mode: a picture
# behind them would be one or the other, and could not say "drag" in thirty languages.
import os.path

application = defines["app"]  # noqa: F821 (dmgbuild defines it)
name = os.path.basename(application)

format = "UDZO"
files = [application]
symlinks = {"Applications": "/Applications"}
icon = defines["icon"]  # noqa: F821 (the volume's icon: the app's)

window_rect = ((200, 200), (560, 300))
icon_size = 128
text_size = 13
icon_locations = {name: (150, 130), "Applications": (410, 130)}
