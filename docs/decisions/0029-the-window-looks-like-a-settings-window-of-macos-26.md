# 0029: The window looks like a settings window of macOS 26, and is drawn by its own views

Date: 2026-10-28. Status: decided.

## The problem

Beside the apps of macOS 26 the window looked dated: a title bar with
the app's name above a second header, a sidebar of thin grey symbols with a three-line subtitle, white boxes with a
hairline edge on a grey ground, and a heavy blue border round the first-run card.

## What was measured (macOS 27.2, Xcode 27.1)

- **What a picture drawn without a screen can show.** `script/preview_setup.sh` draws the window with `ImageRenderer`,
  which draws SwiftUI's own views but not the ones AppKit draws (a `List`, a `Form`, a `NavigationSplitView`, a spinner, a
  link). A window that is never put on screen, drawn with `cacheDisplay(in:to:)`, shows more: the title bar and its
  buttons, toolbar items, a grouped `Form`, `ProgressView`, `Link`, `Picker`, `Toggle`. It does not show the rows of a
  sidebar `List`, the sidebar's own ground (left transparent) or its vibrant symbols, and it draws switches and the
  prominent button as in a window in the background, also with a window and an application that say they are key and
  active and the notifications of becoming so.
- **A window without a title bar** (`.hiddenTitleBar`; the same as a full-size content view under a transparent title
  bar): the close, minimize and zoom buttons are 14-point circles at 9, 32 and 55 points from the left and 9 from the top
  (centred 16 points down), the title bar is 32 points and the window's corners have a radius of 16.
- **A click in that band reaches the window's content**: a hit test at 10, 20 and 28 points from the top lands on the
  `NSHostingView`, so the header's buttons work there. `WindowDragGesture` makes the band move the window.
- **The grouped settings of macOS 26** (`Form` with `.formStyle(.grouped)`): in light the page is white, a group #F7F7F7 and
  a line between rows #EBEBEB; in dark the page is #1C1C1C, a group #232323 and a line #2D2D2D. A group is the page with the
  text colour at about 3.5 percent over it, in both.
- **The switch of macOS 27.2** (`Toggle` with `.switch`, measured in pixels on `preview_setup.sh --real-controls`): a track of 54 by 24
  points, and a knob that is a pill of 32 by 20, 2 points in, with a soft shadow. The stand-in the pictures draw had been a capsule of
  38 by 22 with a round knob, the switch of iOS; it now has these measures.
- **The segmented control of macOS 27.2** (`Picker` with `.segmented`, the same way): a capsule 24 points tall, with the chosen
  segment a capsule of the track's height; in a window in the background the track is grey at 8 percent and the chosen segment
  darker. In a window in front the chosen segment is raised and light, which an offscreen window cannot show: the stand-in draws
  it so, white in light and lighter than the track in dark, instead of the blue-tinted rounded rectangle it had.
- **The checkbox of macOS 27.2** is a 16-point box with corners of about 4 points, drawn by SwiftUI itself (`_FocusRingView` is
  the only view under it), blue with a white check when on and grey when off; `ImageRenderer` draws it, so the symbol that stood
  in for it (smaller and squarer) is gone.
- **The small spinner of macOS 27.2** (`ProgressView` with `.small`, AppKit's): 16 points across, twelve thin spokes. The stand-in
  had eight bolder ones on 13 points; it now has these.

## Decision

1. **The window keeps its own views**, restyled: what `ImageRenderer` draws is what the app draws, so the pictures of the
   window, the gallery of the doctor's sentences and the website's screenshots stay the real window. Where the window uses a
   control that AppKit draws (a switch, a segmented control, a text field, the config's text), the picture shows a stand-in of
   SwiftUI's own views (`#if STANDINS`), and the stand-in is only right while it looks like the control: see 10 and 11, after
   which the value menus and the plain buttons are SwiftUI's own and need none; the checkbox of macOS 26 is SwiftUI's own too
   (a 16-point box with no AppKit view under it, which `ImageRenderer` draws), so it has none either. `preview_setup.sh --real-controls` keeps the
   demo's data and draws the real controls, in a window that is never put on screen.
2. **No title bar.** The sidebar runs from the top of the window to its bottom, with the window's buttons in its corner;
   the page's header stands where a title bar would. A drag there moves the window, and a double-click does what the
   person chose for a title bar (`AppleActionOnDoubleClick`: zoom, minimize or nothing). The preview draws the three
   buttons where macOS puts them.
   - The title bar runs the way the Mac's language does, not the window's (`NSWindow.windowTitlebarLayoutDirection`, which
     the SDK says is right to left when the primary system language is). A window in a language that runs the other way
     (Arabic on an English Mac, English on a Hebrew one) has its sidebar on the other side, and the window's buttons over the
     end of the header: the window reads the direction from its own window, and the header then leaves them 56 points.
     `preview_setup.sh --titlebar-ltr` and `--titlebar-rtl` draw those windows. Found by an independent review, which drew
     the buttons on top of Install or Repair.
3. **The sidebar as System Settings draws its own:** each section's symbol, white, on a tile of the section's colour, and
   the chosen section on the system's colour of a selection (`selectedContentBackgroundColor`, which keeps white text
   readable with a yellow or graphite accent; `unemphasizedSelectedContentBackgroundColor` when the window is in the
   background). The app's name and version stand
   at its top; the subtitle is the tooltip of the name.
4. **One card, without an edge**: `panel()` is the group of macOS 26 (the text colour at 3.5 percent), `callout(_:)` a card
   of one colour for what asks for something (the first steps, a copy of the app to leave, a change waiting for a yes). With
   Increase Contrast both get an edge.
5. **Capsule buttons.** In the header, Open Config is its symbol in a round button, with its words as its tooltip and for
   VoiceOver; Install or Repair keeps its words, which a person looks for when something is wrong, and gives them up only
   when the window is too narrow (it is blue, the default button, when a check asks for it).
6. **The page of one thing** (an agent, a preset, a start option, a template, an app) puts its name in the header, after a
   round back button (⌘[) whose tooltip and VoiceOver label name the page it returns to; the page no longer stacks a link
   back and a second title under the section's. A long name is cut; a section's own name never is.
7. **Settings rows as macOS 26 draws them:** the setting's name at the leading edge, its control at the trailing edge (at
   most 260 points, and it takes its width before the name wraps), what it does under both; a block of text (a template's
   contents, a preset's prompt) stands under its name across the row. The Overview's default terminal, where its sessions
   open, default editor and language are one group of such rows instead of three cards of different shapes.
8. **The page stops growing at 780 points**, its margins included, and a wider window puts it and the header in the middle of the
   space beside the sidebar: in a window as wide as the screen a setting's name and its control were a screen apart. The band of
   the title bar still moves the window across the whole width, and the room the header leaves for the window's buttons
   (decision 2) shrinks as a centred header stands further from them (`SetupModel.headerRoomForWindowButtons`, tested).
   `preview_setup.sh --wide` draws a window 1400 points wide.
   - Both are placed by one inset measured on the space beside the sidebar (`SetupModel.pageInset`), not each centred in its
     own container. Measured by an independent review, in a window that was never put on screen, with scroll bars always
     shown: the scroll view's bar takes 17 points, and a page centred inside the scroll view stood 8.5 points off the header
     (417.5 to 1197.5 against 426 to 1206 in a window 1400 points wide) and moved sideways when the bar came and went. With
     the one inset both stand at 426 to 1206, with and without the bar.
9. **The agents the login shell does not have are a list of their own** under the ones it has, below a line that says "Not found in
   your login shell" once, one line each: the check, the name, the command, How to Install. On a Mac with three agents the page
   had nine lines that each said the same thing beside the same icon, the page's most repeated sight. They keep their check (a
   person may know better than the login shell), and their icon goes, as it is the same on every line.
10. **A value menu draws its label as it is** (`ChoiceMenu`: the default terminal and editor, the language, where a session opens,
    and the choices of the pages of one thing). Measured on macOS 27.2 in a window that was never put on screen
    (`cacheDisplay`): a `Menu` with `.menuStyle(.borderlessButton)` is an AppKit pop-up button (`SwiftUIPopupButton`), which keeps
    the label's text and its first image and draws the image first, so the window showed "⇕ Ghostty" in the system's darker text
    while every picture of it, drawn from the label, showed "Ghostty ⇕"; with an app's icon in the label the chevrons were
    dropped. `.menuStyle(.button)` with `.buttonStyle(.plain)` has no AppKit view under it and draws the label's own views, the
    same as the picture, also disabled and in dark mode. It loses the pop-up button's look under the pointer, so a light ground
    stands under it then. Its role for VoiceOver was read through the accessibility API on the process itself, from a second
    thread, with the window ordered back for a second (SwiftUI builds no accessibility tree for a window the window server
    does not have): it is a menu button, "Default terminal", value "Ghostty", with the actions show menu and press, as the
    pop-up button was; a plain button of a row is a button with the row's name and value, a check a checkbox.
11. **A row that opens a page is a plain button** (`PlainButton`: the rows of Your Apps, the presets, the templates and the start
    options, and the small buttons of words or a symbol). Drawn by `preview_setup.sh --real-controls`, a `.borderless` button, which
    is an AppKit button (`SwiftUIAppKitButton`) holding the label, drew the words of a whole row grey, as a disabled row's: the
    Agents page had its agents in the text colour and its presets grey under them. It did so also with the window and the app
    overriding everything that says they are key, main, active and visible, so it could not be told apart there from the look of a
    window in the background, which is not what the app should depend on either. A `.plain` button has no AppKit view under it and
    draws the label as it is, as the pictures do; its label takes the whole frame for the click (`contentShape`), as the AppKit
    button did.
    `script/verify_window_styles.py`, in the gate and CI, refuses both styles in the window's files, with the reason.
12. **One rule for what stands between and around the groups** (an independent design review of 0.3.20, 2026-10-29). Taken:
    - the Config page's buttons stand at the trailing edge with the one that does it last (Dismiss, Apply; Revert, Save), as
      every other page and a sheet of macOS have them;
    - a line between two rows of a group runs from 14 points in on each side (`RowDivider`), in the groups of settings rows
      (an agent's, a preset's, a template's and an app's page) and in Recent Changes, as in the lists; they ran edge to edge;
    - the checks' titles are in the regular weight, as the names of every other list;
    - a form of Copy Path or a Quick Action that is not in the menu is named in the text's colour, as the agents not in the
      menu are (a grey name looked switched off);
    - a button that acts on a whole page or section is of the regular size everywhere (Test Terminal Launch, Choose Folder,
      Pin a Folder, Clear Recent Folders were small); a button inside a row or a card stays small. Set Up keeps the large
      size: it is the one default button of a first run.

    Considered and left: How to Install moved to the agent's page (decision 9 put it on the row: a control people look for
    belongs on the row); the setup's state said in one place only (the sidebar's footer says it on every
    page); the version in a tooltip; redrawing the first run's chips as plain buttons; the Overview's tiles taken off (decision 7); the glyph repeated on every row of presets, start
    options and templates (little gain; an agent keeps its app's icon where the app is installed).
13. **One spacing for every page** (`PageRhythm`, the same review): 24 points between a page's sections, 8 inside one (its
    heading, what it says, its group and the buttons under it). The pages had their own: 14, 16, 24 or 28 points between
    sections and 8 or 10 inside, and on the pages of one thing (an agent, a preset, a start option) a group's heading, its
    list and its footnote were siblings of the page and stood a section apart. A section is now one stack; on Agents, the
    agents of the menu with what the page says of them, then the ones not in it with Add Your Own Agent. The review also asked
    for one size of explanation and shorter page texts; left: that would change the texts of thirty languages, and German
    already fills two lines.
    A regression review of the three changes measured what the pictures showed: the note of a change (`ConfigEditBanner`),
    empty, still took a place in a section's spacing, so the Finder Menu's sections stood 32 points apart instead of 24; it
    now has no view when it has nothing to say. It also found the Overview's, the Checks' and the Worktrees' own spacings
    left over, a sub-heading ("Not in the Menu" under Copy Path, "Not found in your login shell") as near the list above as
    the one it names (each now 8 points further from the list above), New File's buttons as near the setting under them as
    the list above, and the Config page's status at one edge and its buttons a row below at the other (now one row).
14. **The header is the band of a title bar, on the line of the window's buttons** (the same review). Measured in the
    preview: the header was 56 points tall, its title (22 points) and buttons centred 28 points down, while macOS centres the
    close, minimize and zoom buttons 16 points down; the title stood neither in the band of a title bar nor clearly under
    it. The header is now 32 points tall, the height of a title bar, with the page's title in 15-point bold and its buttons,
    the back button among them, of the small size, all centred on the line of the window's buttons, as a window of macOS 26
    without a toolbar has it; the page starts 12 points under it. Considered: a unified toolbar, under which AppKit centres
    the window's buttons 26 points down and 19 in (measured in a window that was never put on screen), with the header
    centred to match; left, because an empty toolbar changes the window's chrome in ways a window off screen cannot show.
    Checked in the preview's pictures: a section and a page of one thing, German in the smallest window, Arabic with the
    title bar left to right (the header still leaves the window's buttons their room), a wide window, dark, a repair under
    way and an older copy's strip.
    A page that is scrolled is cut under the header at a line, the system's separator, which shows only while the page is
    scrolled (`onScrollGeometryChange`), as a title bar draws one; without it text scrolled under the small buttons was cut off
    bare. Measured in a window that was never put on screen, with the same views: no line at the top, a line one point thick
    at the header's edge once scrolled 100 points, none again back at the top. The scroll edge effect of macOS 26
    (`scrollEdgeEffectStyle`, `.soft` or `.hard`) draws nothing there that `cacheDisplay` shows, so it could not be compared,
    and is not used. The preview draws no scroll view, so its pictures show the top of a page, without the line.
15. **A second review, of 0.3.21.** Taken, each measured or looked at in the pictures:
    - the line between rows is the grouped settings' own colour (`GroupLine`: the text colour at 5.5 percent, measured
      #ECECEC on #F7F7F7 and #2D2D2D on #232323 against macOS's #EBEBEB and #2D2D2D); `Divider` drew #DFDFDF and #393939,
      twice the contrast, and every group read as a ruled table. With Increase Contrast it is darker again;
    - the Finder menu's picture stands in the middle of a stage of the group's colour across the page, not on the bare page at
      its leading edge (the first thing the page and the website's screenshot show);
    - the config's text has the ground and edge of a text field, as a template's contents do; on the group's grey it read as
      the AI Assistants page's snippets, which cannot be changed;
    - the Overview's tiles are the sidebar's 22 points (were 26); the worktrees' symbols are secondary, as every list's leading
      symbol (the accent colour says a thing can be clicked); the cards stacked after a setup and on a first run share one
      inset (18 points); the Config page's status stands on the line of its buttons' words.

    Left: one row height and one leading-symbol size for every list (a shared row view, a larger change than these); the
    lines of the Overview's and the Checks' groups start where the text does, past the tile or symbol, as System Settings
    starts them, and stay so; Start agents without asking as an ordinary row (a setting that lets
    agents act without asking keeps its own card); Copy Path's title as the first row of its list.
    The button that does what a page is for (Save, Apply, Set Up) is blue only while it can be pressed, and the grey capsule
    of the buttons beside it while it cannot (`DefaultButton`), as macOS draws a default button that is off: `.borderedProminent`
    drew it off as a faded blue in the pictures, and a window off screen draws every default button grey, so what the app
    showed could not be told; the style now says it either way.
    The look with Increase Contrast (`GroupLine` and `panel()` draw an edge then) is a manual check: SwiftUI's
    `colorSchemeContrast` can be read but not set (`EnvironmentValues`, macOS 26 SDK), so the preview cannot draw it.

Which page of one thing is open, what the header calls it and where its back button goes are one answer of the model
(`SetupModel.openDetailPage`, `detailHeader`, `closeDetail`), which the sections use too, and the side of the window's buttons
is `SetupModel.windowButtonsOverHeader`: both are tested (`SetupModelDetailHeaderTests`). What can only be seen (a menu line
that is too long, the column of Copy Path's titles) is looked at in the preview's pictures.

These last three came from an independent design review of the restyled window, which prototyped them; it also proposed
icon-only header buttons and drag handles shown only on hover, which were not taken: controls in plain sight had already
been missed, and these would hide more.

## Alternatives

- **`NavigationSplitView`, a `List` sidebar and a toolbar**: the Liquid Glass sidebar of macOS 26 for free, but neither
  renderer draws its sidebar, so every picture of the window would show a stand-in for its most visible part.
- **A sidebar inset from the window's edges, as the glass sidebars of macOS 26 are**: those come with a toolbar, which
  moves the window's buttons 10 points in; without one the close button, 9 points from the edge, sits on the inset
  panel's border.
- **Keep the title bar**: two headers, one above the other.
