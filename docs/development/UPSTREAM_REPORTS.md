# Known upstream issues

Problems found in dependencies, with reproductions prepared for the projects concerned.

## TOMLDecoder 0.4.5: a trap on a table header cut off after an empty quoted key

Found by fuzzing the config parser (see `docs/decisions/0008-independent-review.md`, "Extended fuzzing").

`TOMLTable(source:)` traps (a `Fatal error` inside the Swift standard library, not a thrown `TOMLError`) when the
text ends right after an empty quoted key inside an open bracket:

| input | result |
|---|---|
| `[""` | trap |
| `['']` with single quotes, cut after the second quote: `[''` | trap |
| `[ ""` | trap |
| `[[""` | trap |
| `[a.""` | trap |
| `[""` followed by a line break | `Syntax error: invalid key.` (correct) |
| `x = ""` | parses |

Minimal reproduction, a scratch package that depends on `TOMLDecoder` 0.4.5:

```swift
import TOMLDecoder
do { _ = try TOMLTable(source: "[\"\"") } catch { print(error) }   // expected: a thrown syntax error
```

Expected: a thrown `TOMLError` (as for the same text with a trailing line break). Observed: the process aborts, so
a program that parses user-edited files dies on a file that was saved half-way.

Not diagnosed in the library's source; the pattern (it needs the end of the input right after the closing quote of
an empty key, and one more byte avoids it) points at an index read one past the end of the buffer.

Workaround used here (`ConfigParser.parse`): the text is given to the library with a final line break added.

## Swift 6.3.2: the optimizer never finishes on a large nested dictionary literal

Found when `script/install_local.sh` sat on `Compiling RightHereCore` for ever (macOS 26.5, the command-line tools
of Xcode 26.5, `swift-driver 1.148.6 Apple Swift version 6.3.2 (swiftlang-6.3.2.1.108)`).

The static initializer of a `[String: [String: String]]` literal with 157 keys, each a literal of 30 strings (the
compiled localization catalog, 4,710 strings), never comes out of the SIL optimizer in a release build (`-O`,
whole module). A debug build compiles it in seconds.

Where it spins (`sample` of the `swift-frontend` process after nine minutes, every sample in the same frame):

```
COWArrayOptPass::run()
  swift::ColdBlockInfo::analyze(swift::SILFunction*)
```

and `-Xllvm -sil-print-pass-name` names the function: `$s13RightHereCore13LocalizationsO5table_WZ`, the
initializer of `Localizations.table`, pass 17 of the mid-level function pipeline, `COWArrayOpts (cowarray-opt)`.

| compile of `RightHereCore` in release | time |
|---|---|
| as is | not finished after 9 minutes (killed) |
| with `-Xllvm -sil-disable-pass=cowarray-opt` | 23 seconds |
| the table as one dictionary per key (the workaround below) | the whole `rh` product in 53 seconds |

Expected: the pass finishes, as it does for the same data split into smaller literals. Observed: a hang, with no
output, that looks like a build still running.

Workaround used here (`script/compile_localizations.py`, `render_table`): the generated file holds one
`private static let` dictionary per key and `Localizations.table` is a literal that only gathers them. Nothing else
changed; `Localizer` still reads `Localizations.table[key]`.
