import Foundation

/// What to tell a person about a text the TOML library refuses: the line the trouble is on and what is wrong, in this
/// project's words. The library reports where it gave up and how it felt about it ("Internal error" for an array that was
/// never closed, the end of the file as the place), which is no help to someone fixing a file by hand.
///
/// `TOMLError`'s reason is not public, so the library's sentence is what is matched; every sentence mapped here is pinned by
/// a test that feeds the library a text that makes it say so, so a new version that rephrases one fails loudly.
enum TOMLSyntax {
    struct Explanation: Equatable {
        var line: Int?
        var message: String
    }

    static func explain(_ description: String, outline: TOMLOutline) -> Explanation {
        var line: Int?
        var text = description
        if let match = description.firstMatch(of: #/^\(Line (\d+)\) /#) {
            line = Int(match.1)
            text = String(description[match.range.upperBound...])
        }
        if text.hasSuffix(".") { text.removeLast() }
        // The library counts the line break it adds after the last line, and the end of the text, as lines of their own.
        line = line.map(outline.clamped)

        switch text {
        case "Internal error":
            // Reached at the end of an array or inline table whose closing bracket is not where it should be.
            if let problem = outline.problem { return Explanation(line: problem.line, message: problem.message) }
            return Explanation(line: line, message: "an array or inline table is not closed, or two of its items have no comma between them")
        case "Syntax error: invalid key", "Syntax error: expects ]", "Syntax error: expects ]]":
            if let problem = outline.problem, problem.message.hasPrefix("table header not closed") {
                return Explanation(line: problem.line, message: problem.message)
            }
        default:
            break
        }
        return Explanation(line: line, message: message(for: text))
    }

    private static let keyAdvice = "a key is made of letters, digits, `-` and `_`; anything else goes in \"quotes\""

    private static func message(for text: String) -> String {
        switch text {
        case "Syntax error: invalid key": "invalid key: \(keyAdvice)"
        case "Syntax error: invalid or missing key": "a table header needs a name between its brackets, like `[general]`"
        case "Syntax error: expects ]": "table header not closed: missing `]`"
        case "Syntax error: expects ]]": "table header not closed: missing `]]`"
        case "Syntax error: extra chars after ] or ]]": "extra text after the table header; put it on a line of its own"
        case "Syntax error: syntax error": "a value is missing or misplaced here: nothing after `=`, or a stray `,`"
        case "Syntax error: missing =": "missing `=` after the key (\(keyAdvice))"
        case "Syntax error: extra chars after value": "extra text after the value on the same line; text needs \"quotes\", and each setting goes on a line of its own"
        case "Syntax error: unterminated quote": "text in \"double quotes\" is not closed: a closing `\"` is missing on this line (use `\"\"\"` for text over several lines)"
        case "Syntax error: unterminated s-quote": "text in 'single quotes' is not closed: a closing `'` is missing on this line"
        case "Syntax error: unterminated triple-d-quote": "text that starts with `\"\"\"` is never closed"
        case "Syntax error: unterminated triple-s-quote": "text that starts with `'''` is never closed"
        case "Syntax error: bare carriage return is not allowed": "a carriage return without a line feed (an old Mac line ending); use ordinary line breaks"
        case "Syntax error: control characters are not allowed in comments": "a control character in a comment; remove it"
        case "Syntax error: expect a string": "an inline table `{ }` holds `key = value` entries"
        case "Syntax error: cannot add to inline table", "Syntax error: cannot insert new entry into existing table",
             "Syntax error: cannot add to explicitly defined table using dotted keys":
            "a table written as `{ ... }` or with dotted keys is complete where it is written: add keys there, not elsewhere"
        case "Syntax error: array mismatch": "`[[name]]` and `[name]` cannot both be used for the same name"
        case "Key already exists": "this key or table is defined twice; each can be written once, so merge the two"
        case "Ill-formed key": "this key is already set in this table"
        default:
            text.hasPrefix("Syntax error: ") ? String(text.dropFirst("Syntax error: ".count)) : text
        }
    }
}
