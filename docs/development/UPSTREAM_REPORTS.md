# Reports to send upstream

Drafts for problems found in dependencies. Nothing here has been sent; filing is the owner's call.

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
