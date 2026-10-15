"""Finds the text a SwiftUI view shows that is a string literal, which is text the String Catalog does not know.

`Text("Overview")` looks the text up as a key of a catalog of the app's own, finds none (the catalog is compiled into Swift by
compile_localizations.py, and is read through `Localizer`) and shows the English. So do `Button("..")`, `Label("..")`, `.help("..")`
and the other calls below: a view that does that is English in thirty languages and nothing in the build says so.

What a window shows goes through `Localizer` (`Text(l10n.string(.appAllSet))`), and what is only a name or a command is written
`Text(verbatim: "rh")`. This module reads Swift source, tokenizes it far enough to find a call and its first argument, and reports
each string literal with a letter in it that is there. It does not understand Swift: a literal inside a nested call
(`Text(Self.styled("x"))`) is not seen, so the check is a net and not a proof. verify_localizations.py runs `self_test` before it
looks at the code, so that a net that has stopped catching what it is for fails the build.
"""
from dataclasses import dataclass

# Views and modifiers whose first, unlabeled argument is the text they show or speak.
VIEWS = {
    "Text", "Button", "Label", "Toggle", "Section", "Picker", "Menu", "TextField", "SecureField", "Link", "GroupBox", "DisclosureGroup",
    "LabeledContent", "ProgressView", "Window", "ContentUnavailableView", "Stepper", "Gauge", "NavigationLink", "TextEditor",
}
MODIFIERS = {
    "help", "navigationTitle", "navigationSubtitle", "accessibilityLabel", "accessibilityHint", "accessibilityValue", "badge", "alert",
    "confirmationDialog",
}
# Product names that may be written as a literal.
ALLOWED = {"Right Here"}


@dataclass(frozen=True)
class Token:
    kind: str  # "id", "str" or "punct"
    text: str  # for a string: what it says, without its interpolations
    line: int


@dataclass(frozen=True)
class Finding:
    line: int
    call: str
    text: str


def _raw_string_starts(source: str, index: int) -> bool:
    """Whether `#"` or `##"` begins at `index`: a raw string."""
    j = index
    while j < len(source) and source[j] == "#":
        j += 1
    return j > index and j < len(source) and source[j] == '"'


def _read_string(source: str, start: int) -> tuple[str, int, int]:
    """Reads the literal that begins at `start` (`"`, `\"\"\"` or a raw string). Returns what it says without its interpolations,
    the index after it, and how many line breaks it spans."""
    n = len(source)
    hashes = 0
    j = start
    while source[j] == "#":
        hashes += 1
        j += 1
    multiline = source.startswith('"""', j)
    j += 3 if multiline else 1
    closing = ('"""' if multiline else '"') + "#" * hashes
    escape = "\\" + "#" * hashes
    text: list[str] = []
    breaks = 0
    while j < n:
        if source.startswith(closing, j):
            return "".join(text), j + len(closing), breaks
        if source.startswith(escape + "(", j):
            j += len(escape) + 1
            depth = 1
            while j < n and depth:
                if source[j] == '"':
                    _, j, inner = _read_string(source, j)
                    breaks += inner
                    continue
                depth += (source[j] == "(") - (source[j] == ")")
                breaks += source[j] == "\n"
                j += 1
            continue
        if source.startswith(escape, j) and j + len(escape) < n:
            following = source[j + len(escape)]
            j += len(escape) + 1
            if following == "u" and j < n and source[j] == "{":
                while j < n and source[j] != "}":
                    j += 1
                j += 1
                text.append("�")
            elif following in "ntr0":
                text.append(" ")
            else:
                text.append(following)
                breaks += following == "\n"
            continue
        breaks += source[j] == "\n"
        text.append(source[j])
        j += 1
    return "".join(text), n, breaks


def tokenize(source: str) -> list[Token]:
    tokens: list[Token] = []
    i, line, n = 0, 1, len(source)
    while i < n:
        c = source[i]
        if c == "\n":
            line += 1
            i += 1
        elif c.isspace():
            i += 1
        elif source.startswith("//", i):
            while i < n and source[i] != "\n":
                i += 1
        elif source.startswith("/*", i):
            depth = 1
            i += 2
            while i < n and depth:
                if source.startswith("/*", i):
                    depth += 1
                    i += 2
                elif source.startswith("*/", i):
                    depth -= 1
                    i += 2
                else:
                    line += source[i] == "\n"
                    i += 1
        elif c == '"' or (c == "#" and _raw_string_starts(source, i)):
            text, end, breaks = _read_string(source, i)
            tokens.append(Token("str", text, line))
            line += breaks
            i = end
        elif c.isalpha() or c == "_":
            j = i
            while j < n and (source[j].isalnum() or source[j] == "_"):
                j += 1
            tokens.append(Token("id", source[i:j], line))
            i = j
        else:
            tokens.append(Token("punct", c, line))
            i += 1
    return tokens


def _is(token: Token | None, kind: str, text: str) -> bool:
    return token is not None and token.kind == kind and token.text == text


def first_argument(tokens: list[Token], open_index: int) -> list[Token]:
    """The string literals of the first argument of the call whose `(` is at `open_index`, at the depth of the call: up to the first
    comma or the closing bracket. A labeled first argument (`verbatim:`, `action:`, `value:`) is not text and gives nothing."""
    inside = tokens[open_index + 1:]
    if len(inside) >= 2 and inside[0].kind == "id" and _is(inside[1], "punct", ":"):
        return []
    found: list[Token] = []
    depth = 0
    for token in inside:
        if token.kind == "punct" and token.text in "([{":
            depth += 1
        elif token.kind == "punct" and token.text in ")]}":
            if depth == 0:
                break
            depth -= 1
        elif _is(token, "punct", ",") and depth == 0:
            break
        elif depth == 0 and token.kind == "str":
            found.append(token)
    return found


def find_literals(source: str) -> list[Finding]:
    """Every string literal with a letter in it that a view or a modifier of the lists above is given as its text, except the product names."""
    tokens = tokenize(source)
    findings: list[Finding] = []
    for index, token in enumerate(tokens):
        following = tokens[index + 1] if index + 1 < len(tokens) else None
        third = tokens[index + 2] if index + 2 < len(tokens) else None
        if token.kind == "id" and token.text in VIEWS and _is(following, "punct", "("):
            if index > 0 and _is(tokens[index - 1], "punct", "."):
                continue
            name, opening = token.text, index + 1
        elif _is(token, "punct", ".") and following is not None and following.kind == "id" and following.text in MODIFIERS and _is(third, "punct", "("):
            name, opening = "." + following.text, index + 2
        else:
            continue
        for literal in first_argument(tokens, opening):
            if any(character.isalpha() for character in literal.text) and literal.text not in ALLOWED:
                findings.append(Finding(literal.line, name, literal.text))
    return findings


# What the check must flag and what it must leave alone, as a line of a view and the findings it gives, `(call, text)`. verify_localizations.py
# runs these on every verification, so a change to the scanner that stops it seeing a literal fails the build instead of passing everything.
FLAGGED: list[tuple[str, list[tuple[str, str]]]] = [
    ('Text("Overview")', [("Text", "Overview")]),
    ('Button("Remove") { go() }', [("Button", "Remove")]),
    ('Label("Quick Actions", systemImage: "bolt")', [("Label", "Quick Actions")]),
    ('Toggle("Launch at login", isOn: $on)', [("Toggle", "Launch at login")]),
    ('Section("Pinned") { rows }', [("Section", "Pinned")]),
    ('Picker("Terminal", selection: $choice) { options }', [("Picker", "Terminal")]),
    ('Text(attention ? "Needs attention" : "All set")', [("Text", "Needs attention"), ("Text", "All set")]),
    ('Text("\\(count) folders")', [("Text", " folders")]),
    ('Text("Version \\(Self.version(for: "x"))")', [("Text", "Version ")]),
    ('Text("""\n    Several\n    lines\n    """)', [("Text", "\n    Several\n    lines\n    ")]),
    ('Image(systemName: "gear").help("Settings")', [(".help", "Settings")]),
    ('Circle().accessibilityLabel("Status")', [(".accessibilityLabel", "Status")]),
    ('row.accessibilityHint("Opens the list").accessibilityValue("Expanded")', [(".accessibilityHint", "Opens the list"), (".accessibilityValue", "Expanded")]),
    ('content.navigationTitle("Setup")', [(".navigationTitle", "Setup")]),
    ('Text(l10n.string(.appAllSet)).help("Hint")', [(".help", "Hint")]),
    ('Window("Setup", id: "main") { Root() }', [("Window", "Setup")]),
    ('Text("Caf\\u{E9} \\n")', [("Text", "Caf�  ")]),
    ('Text(#"raw "text""#)', [("Text", 'raw "text"')]),
]
SPARED: list[str] = [
    'Text(verbatim: "rh")',
    'Text(l10n.string(.appAllSet))',
    'Text(verbatim: AppIdentity.productName)',
    'Text("Right Here")',
    'Text("\\(count)")',
    'Text("12")',
    'Text("\\n")',
    'Text("\\u{1F600}")',
    'Button(action: { model.copy("not a title") }) { Image(systemName: "doc.on.doc") }',
    'Button(l10n.string(.appOpenConfig)) { model.open("kept") }',
    'Label(title, systemImage: "gearshape")',
    'Image(systemName: "gearshape")',
    'Text(Self.styled("Nested call"))',
    'Text(l10n.render(.menuOpenIn("Ghostty")))',
    'content.accessibilityElement(children: .combine)',
    'Divider().accessibilityHidden(true)',
    'Text(text).help(l10n.string(.appCheckAgain))',
    'Rectangle().badge(count)',
    'Window(AppIdentity.productName, id: "main") { Root() }',
    '// Text("In a comment")',
    '/* Button("In a block comment") */',
    'let name = "Not shown: a plain string"',
    'Text(verbatim: "Right Here").help(l10n.string(.appCheckAgain))',
    '#if PREVIEW\n    content\n    #else\n    ScrollView { content }\n    #endif',
]


def self_test() -> list[str]:
    """Problems with the scanner itself, as lines for the verifier; none when it sees what it should."""
    problems = []
    for snippet, expected in FLAGGED:
        found = [(finding.call, finding.text) for finding in find_literals(snippet)]
        if found != expected:
            problems.append(f"swiftui_literals: {snippet!r} gave {found}, expected {expected}")
    for snippet in SPARED:
        found = [(finding.call, finding.text) for finding in find_literals(snippet)]
        if found:
            problems.append(f"swiftui_literals: {snippet!r} is fine but was flagged: {found}")
    return problems
