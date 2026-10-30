# 0028: The app icon is an Icon Composer document: a prompt in a pin

Date: 2026-10-28. Status: decided.

## The problem

Beside the apps of macOS 26 the app looked dated, the icon included. The icon was a picture: a neon crosshair
around `>_`, in a folder, in a chrome bezel, on a dark ground, cut into the sizes of an `AppIcon.appiconset` by a script.
At 16 and 32 pixels, the sizes of Finder's menu and a list row, its detail ran together; it had one look, which macOS 26
tints and clears by itself when the person chooses a tinted or clear Dock; and the picture and its source (1.5 MB) were
also copied into the app as resources, because they lay in the folder whose files the app target takes.

## Decision

1. **A white pin that holds a `>_` prompt, standing on a small glass disc, on a violet-to-blue ground**: a prompt, right
   here. One shape, which is still a pin at 16 pixels, and not a terminal or a folder, which the icons beside it in the
   Dock and in the menu already are.
2. **The source is `Apps/RightHere/AppIcon.icon`**, the document Icon Composer (Xcode 26 and later) reads and writes:
   `icon.json` and one SVG per layer (`prompt`, `pin`, `ground`), each a Liquid Glass layer. macOS draws its light, dark,
   tinted and clear looks from it.
3. **Places that cannot read it get one PNG**, `docs/images/icon.png`, which `script/export_icon.py` draws with Xcode's
   `ictool`: the light look, its body 824 of 1024 pixels like every icon in the Dock. The README, the setup window's
   preview and the website use it.
4. **Finder's toolbar button is the pin and the prompt in lines** (`rh-toolbar`, drawn by `script/generate_menu_icons.swift`
   with the menu's glyphs: a 16-point template image, a 1.25-point round stroke), so that among Finder's own buttons it is
   the app's and not a generic menu symbol. The glass disc is left out: at that size it is a smudge.

## What was measured (Xcode 27.1, XcodeGen 2.45.4, macOS 27.2)

- XcodeGen files `AppIcon.icon` as one resource (`wrapper.icon`), not as a folder of files.
- `actool` compiles it into `Assets.car` with renditions for `NSAppearanceNameAqua`, `NSAppearanceNameDarkAqua` and
  `ISAppearanceTintable`, writes an `AppIcon.icns` (16 to 256 pixels) beside it, and sets `CFBundleIconName` and
  `CFBundleIconFile` to `AppIcon`; `ASSETCATALOG_COMPILER_APPICON_NAME` stays `AppIcon`.
- `NSWorkspace.icon(forFile:)` of the built app draws it with its body at 412 of 512 pixels, the same as Terminal's and
  Finder's.
- `ictool --export-image` draws the shape to the edges of the image it writes, without the grid's margin; the export
  script adds the margin.

## Alternatives

- **A folder with `>_` on its face.** The plainest meaning, and it looks like the Terminal icon beside it.
- **A pin with only a chevron.** Clear at every size, but it reads as navigation, not as a prompt.
- **A folder with a red map pin dropped on it.** Literal, but it says where, not what happens there.
- **The same pin on an orange-to-pink ground.** As good in every look; orange is the colour of Claude, one of the agents
  the menu names, and the icon should not look like theirs.
- **PNGs exported from Icon Composer into the old `.appiconset`.** One look in every appearance, and the margin by hand.

The candidates were drawn with `ictool` in the Default, Dark, TintedDark and ClearLight looks and at 128, 32 and 16
pixels, beside Terminal, Finder and Ghostty as `NSWorkspace` draws them, and chosen from that sheet.

**2026-10-29, the prompt in dark.** Drawn again in all six looks of macOS (`ictool --rendition`), the Dark look showed what
the sheet had passed over: macOS gives the pin the ground's violet in dark, so the indigo `>_` stood violet on violet and
nearly vanished, in the look of everyone who uses dark mode. The prompt layer now has a fill for the dark appearance
(`fill-specializations`, white), and is white on the violet pin there; the Default, ClearLight, ClearDark, TintedLight and
TintedDark looks are the same, pixel for pixel. A fill for the `tinted` appearance was tried and left: it covers the Clear
looks too, where a white prompt vanishes on the white pin. TintedDark keeps a dark prompt on a purple pin, which macOS
derives from the tint. `actool` keeps the fill: the built app's `Assets.car` (`assetutil --info`) has the white beside the
ground's two colours and an icon group for `NSAppearanceNameDarkAqua`. What a Mac shows in dark is a manual check (the
icon's look follows System Settings › Appearance › Icon & widget style, which a drawing appearance does not switch).
