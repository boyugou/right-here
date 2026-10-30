# 0027: What goes to Finder is small, is never waited for, and has no separators where Finder draws them as empty rows

Date: 2026-10-16. Status: decided; not yet checked on a real Finder on macOS 26 after the change.

## The reports

Two reports from the 0.3.2 release on macOS 26.5.1 (25F80):

- **A late menu:** after a right-click the Right Here entries show about a second late.
- **Empty rows:** a screenshot of Finder's menu: where the menu has a separator, Finder draws an empty row of the height of an entry, in the menu ("More Agent Options", then a gap, then "New File") and in
  the "Open With" submenu (iTerm, a gap, Cursor). The setup window, which draws its own lines, shows a line there.

## What was measured

Finder asks the extension for its items when the menu opens (`menuNeedsUpdate:` of its extension host) and draws what comes back, so the extension's reply is part of what the person waits for.

- **Our own time is small.** On macOS 27.2 (Apple silicon), building the menu from cold facts takes 3 to 15 ms and the icons 3 to 73 ms the first time in a process; the config read 2 ms.
- **The icons are not small.** `NSWorkspace.icon(forFile:)` returns an image that holds every size of the icon: 32 representations, 72 MB as TIFF for one app. `size = 16` changes how it is
  drawn, not what it holds. Archiving three menu items with such icons took 560 ms and produced 210 MB; the same three icons drawn into one 48 x 48 bitmap each took 2 ms and 30 KB (three pixels to
  the point, so that a Retina menu and the window's 18-point rows are both sharp). Whatever the exact encoding Finder's host uses (it takes the images as data), a menu of fifteen apps that weighs hundreds
  of megabytes before it is sent is the likeliest second.
- **A menu older than 30 seconds was built again on the click** (`MenuCachePolicy`): thirty LaunchServices lookups and the icons, on the thread that Finder was waiting for.

## Decision

1. **`IconProvider` flattens every app and file-type icon to one bitmap**, three pixels to the point, and says why in a comment (`flattened`). A test holds it: one representation, 48 x 48 pixels, a weight
   under 100 KB, and most of the square drawn (a first version drew the icon into a third of the bitmap because the context counts pixels, and was caught by that).
2. **A menu that is old is served and renewed in the background** (`MenuCachePolicy.Freshness`: fresh, stale, unusable). A stale menu is the same config built more than 30 seconds ago; it is given to Finder
   at once, a new one is built on a background queue after what is installed is asked again (`CachingSystemFacts.expire`), and the next click gets that. The price is one click with an entry for an app that
   was uninstalled meanwhile (running it says the app is not there), where the menu used to be made fresh at the cost of the wait. A config that changed is still never served.
3. **Where Finder draws a separator as an empty row, the menu goes without separators.** `FinderMenuPresentation.showsSeparators` is false below macOS 27, and `nodes(_:separators:)` leaves the separators out at
   every depth; the extension applies it before it builds the `NSMenu`, and the setup window's preview applies it too (`SetupLoader`), so that the window shows what Finder shows. `rh menu`, the editor's rows and
   the config are unchanged: `"-"` stays a valid item, and it is a line on macOS 27, where nobody has seen it drawn as a gap. This is the narrowest change that fits the evidence, which is one screenshot of
   one version.

## Alternatives

- **Keep the separators and call the gap a Finder bug.** To a person it is a bug of Right Here's, and a gap that wide looks like one.
- **Replace a separator with a disabled item showing a line of box-drawing characters.** It is a full row like the gap, and dimmed text in a Liquid Glass menu looks worse than a gap.
- **Never emit separators on any macOS.** It would remove a working feature of macOS 27 on the evidence of 26.
- **Cut the cache lifetime's effect by making the lifetime longer.** It would make the menu offer an uninstalled app for longer without making the rebuild faster.

## What is not known

Whether Finder on macOS 27 draws the separators as lines (no gap has been reported on 27.2, and nobody looked on purpose). Whether the megabytes of icon data made the second, or the background rebuild,
or both. The extension's own timings say it on a Mac that shows the delay
(`log show --last 5m --predicate 'subsystem == "com.boyugou.righthere.FinderExtension"'`: each right-click logs how long `menu(for:)` took and whether the menu came from the cache).
