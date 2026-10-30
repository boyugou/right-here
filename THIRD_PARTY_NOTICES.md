# Third-party notices

Right Here is licensed under the Apache License 2.0 (see `LICENSE`). It includes the following
third-party software, compiled into the `rh` command-line tool and the app.

## TOMLDecoder 0.4.5

https://github.com/dduan/TOMLDecoder. Parses the config file. MIT License:

The MIT License (MIT)

Copyright (c) 2019 TOMLDecoder contributors

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

## swift-argument-parser 1.8.2

https://github.com/apple/swift-argument-parser. Parses the command line. Apache License 2.0 with the
Runtime Library Exception (the license text is the same as `LICENSE` in this repository, plus the
exception below):

    As an exception, if you use this Software to compile your source code and
    portions of this Software are embedded into the binary product as a result,
    you may redistribute such product without providing attribution as would
    otherwise be required by Sections 4(a), 4(b) and 4(d) of the License.

## Provenance of artwork and names

- The app icon is original artwork: the Icon Composer document `Apps/RightHere/AppIcon.icon`, whose shapes are the SVG
  files in it, licensed under Apache-2.0 with the rest of the repository.
- The Finder menu's symbols (`Apps/FinderExtension/Assets.xcassets/rh-*`) are drawn in code by
  `script/generate_menu_icons.swift`, and the pictures `docs/images/demo.svg` and `demo-static.svg` are drawn by hand.
  Both are original and licensed under Apache-2.0 with the rest of the repository.
- Icons of third-party apps shown in menus and in the setup window are read from the person's own installed apps at
  run time. The app and `rh` do not include them, and the pictures of the window in this repository and on the website
  draw plain tiles in their place.
- Product names such as Ghostty, Claude, Claude Code, Codex, Gemini CLI, Microsoft Word, Excel and PowerPoint, Terminal and Finder are
  used only to refer to those products (nominative use). Right Here is not affiliated with, endorsed by or sponsored by their owners.
