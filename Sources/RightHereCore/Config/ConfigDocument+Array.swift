import Foundation

/// An array of strings as it is written, taken apart so that an element can be added, removed or moved with everything else left as it was: the line breaks,
/// the indentation, the comma after the last element, and the comments (a comment line directly above an element, and a comment at the end of its line,
/// belong to that element and travel with it).
///
/// Taking an array apart and putting it together again gives the same text. Nested arrays and inline tables are not read (`nil`): the config has none.
struct TOMLArrayText: Equatable {
    /// What stands between the previous element (or the `[`) and this one.
    struct Before: Equatable {
        /// What follows the previous token on its own line, before the line break: usually nothing, or the space of `[ "a"`.
        var head: String
        /// Comment lines and blank lines between the elements, each as written; they belong to the element.
        var lines: [String]
        /// The indentation of the element's own line.
        var indent: String
        /// Whether the element is on a line of its own.
        var hasNewline: Bool

        init(head: String = "", lines: [String] = [], indent: String = "", hasNewline: Bool = false) {
            self.head = head
            self.lines = lines
            self.indent = indent
            self.hasNewline = hasNewline
        }

        init(_ raw: String) {
            let pieces = raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            head = pieces[0]
            if pieces.count == 1 {
                lines = []
                indent = ""
                hasNewline = false
            } else {
                lines = Array(pieces[1..<(pieces.count - 1)])
                indent = pieces[pieces.count - 1]
                hasNewline = true
            }
        }

        var rendered: String {
            head + lines.map { "\n" + $0 }.joined() + (hasNewline ? "\n" + indent : "")
        }

        /// The same place in the text, without the comments of whoever stood there.
        var position: Before { Before(head: head, lines: [], indent: indent, hasNewline: hasNewline) }
    }

    struct Element: Equatable {
        var before: Before
        var text: String
        /// The comment at the end of the element's line, with the space before it.
        var comment: String
    }

    var elements: [Element]
    /// Whether the last element is followed by a comma.
    var trailingComma: Bool
    /// What follows the last element, up to the `]`.
    var tail: String

    init?(_ raw: String) {
        let bytes = Array(raw.utf8)
        guard bytes.count >= 2, bytes[0] == UInt8(ascii: "["), bytes[bytes.count - 1] == UInt8(ascii: "]") else { return nil }
        func skipSpaces(_ start: Int) -> Int {
            var index = start
            while index < bytes.count, bytes[index] == UInt8(ascii: " ") || bytes[index] == UInt8(ascii: "\t") { index += 1 }
            return index
        }
        func skipTrivia(_ start: Int) -> Int {
            var index = start
            while index < bytes.count {
                switch bytes[index] {
                case UInt8(ascii: " "), UInt8(ascii: "\t"), UInt8(ascii: "\r"), UInt8(ascii: "\n"): index += 1
                case UInt8(ascii: "#"): while index < bytes.count, bytes[index] != UInt8(ascii: "\n") { index += 1 }
                default: return index
                }
            }
            return index
        }
        var found: [Element] = []
        var lastComma = false
        var index = 1
        var needsEnd = false
        while true {
            let triviaStart = index
            index = skipTrivia(index)
            guard index < bytes.count else { return nil }
            if bytes[index] == UInt8(ascii: "]") {
                guard index == bytes.count - 1 else { return nil }
                elements = found
                trailingComma = lastComma
                tail = String(decoding: bytes[triviaStart..<index], as: UTF8.self)
                return
            }
            guard !needsEnd else { return nil }
            let before = Before(String(decoding: bytes[triviaStart..<index], as: UTF8.self))
            let start = index
            let end: Int
            switch bytes[index] {
            case UInt8(ascii: "\""), UInt8(ascii: "'"):
                let string = TOMLScan.skipString(bytes, at: index)
                guard string.terminated else { return nil }
                end = string.end
            case UInt8(ascii: "["), UInt8(ascii: "{"):
                return nil
            default:
                var stop = index
                while stop < bytes.count, ![UInt8(ascii: ","), UInt8(ascii: "]"), UInt8(ascii: "#"), UInt8(ascii: "\n")].contains(bytes[stop]) { stop += 1 }
                while stop > index, bytes[stop - 1] == UInt8(ascii: " ") || bytes[stop - 1] == UInt8(ascii: "\t") || bytes[stop - 1] == UInt8(ascii: "\r") { stop -= 1 }
                guard stop > index else { return nil }
                end = stop
            }
            index = end
            var comma = false
            let afterElement = skipSpaces(index)
            if afterElement < bytes.count, bytes[afterElement] == UInt8(ascii: ",") {
                comma = true
                index = afterElement + 1
            }
            var comment = ""
            let beforeComment = skipSpaces(index)
            if beforeComment < bytes.count, bytes[beforeComment] == UInt8(ascii: "#") {
                var stop = beforeComment
                while stop < bytes.count, bytes[stop] != UInt8(ascii: "\n") { stop += 1 }
                while stop > beforeComment, bytes[stop - 1] == UInt8(ascii: "\r") { stop -= 1 }
                comment = String(decoding: bytes[index..<stop], as: UTF8.self)
                index = stop
            }
            found.append(Element(before: before, text: String(decoding: bytes[start..<end], as: UTF8.self), comment: comment))
            lastComma = comma
            needsEnd = !comma
        }
    }

    private init(elements: [Element], trailingComma: Bool, tail: String) {
        self.elements = elements
        self.trailingComma = trailingComma
        self.tail = tail
    }

    func rendered() -> String {
        var out = "["
        for (index, element) in elements.enumerated() {
            out += element.before.rendered + element.text
            if index < elements.count - 1 || trailingComma { out += "," }
            out += element.comment
        }
        return out + tail + "]"
    }

    // MARK: Editing

    /// Puts a new element at an index of the elements: laid out like the one that is there now, or the last one.
    mutating func insert(_ text: String, at index: Int) {
        if elements.isEmpty {
            if tail.contains("\n") {
                // The comments of a list that has no item yet are the list's: they stay, under the new item.
                elements = [Element(before: Before(head: "", lines: [], indent: "    ", hasNewline: true), text: text, comment: "")]
                trailingComma = true
                tail = tail.hasPrefix("\n") ? tail : "\n" + tail
            } else {
                elements = [Element(before: Before(), text: text, comment: "")]
                trailingComma = false
            }
            return
        }
        // The places are positional, as in `remove` and `move`: what stood at the first place (right after the `[`) is not what stands at the second.
        // The new last element is laid out like the one that was last. An element added at the end of a list with no comma after its last one makes
        // the old last one need a comma: rendering gives it one.
        let places = positions + [Self.place(at: positions.count, in: positions)]
        elements.insert(Element(before: Before(), text: text, comment: ""), at: index)
        relayout(keepingPositionsOf: places)
    }

    /// Takes an element out with its comments; the places stay where they were.
    mutating func remove(at index: Int) {
        let places = positions
        let bracketComment = elements.first?.before.head ?? ""
        elements.remove(at: index)
        guard !elements.isEmpty else {
            // What stands on the line of the `[` and what stands before the `]` is the list's, and stays: only the item's own comments go with it.
            let rest = tail.contains("#") ? tail : (tail.contains("\n") ? "\n" : "")
            tail = bracketComment.contains("#") ? bracketComment + (rest.hasPrefix("\n") ? rest : "\n" + rest) : rest
            trailingComma = false
            return
        }
        // The places are positional: the element that comes first now stands where the first stood, and so on.
        relayout(keepingPositionsOf: Array(places.dropLast()))
    }

    /// Writes another text as the element at an index: the comments above it and at the end of its line stay, and so does the place.
    mutating func replace(at index: Int, with text: String) {
        elements[index].text = text
    }

    /// Moves an element, with its comments, to another index; the places stay where they were.
    mutating func move(from: Int, to: Int) {
        guard from != to else { return }
        let places = positions
        let moved = elements.remove(at: from)
        elements.insert(moved, at: to)
        relayout(keepingPositionsOf: places)
    }

    /// The same layout, holding other elements (no comments).
    func replacingElements(with items: [String]) -> TOMLArrayText {
        var copy = self
        guard !items.isEmpty else {
            copy.elements = []
            copy.trailingComma = false
            copy.tail = tail.contains("\n") ? "\n" : ""
            return copy
        }
        let places = positions
        let isMultiline = rendered().contains("\n")
        copy.elements = items.enumerated().map { index, item in
            Element(before: Self.place(at: index, in: places).position, text: item, comment: "")
        }
        if elements.isEmpty {
            // An empty array has no layout of its own: one line, unless it was written across lines.
            let oneLine = "[" + items.joined(separator: ", ") + "]"
            if tail.contains("\n") || oneLine.count > 100 {
                copy.elements = items.map { Element(before: Before(head: "", lines: [], indent: "    ", hasNewline: true), text: $0, comment: "") }
                copy.trailingComma = true
                copy.tail = "\n"
            } else {
                copy.elements = items.enumerated().map { Element(before: Before(), text: $1, comment: "") }
                copy.trailingComma = false
                copy.tail = ""
            }
        } else if !isMultiline {
            copy.trailingComma = false
            let oneLine = copy.rendered()
            if oneLine.count > 100 {
                copy.elements = items.map { Element(before: Before(head: "", lines: [], indent: "    ", hasNewline: true), text: $0, comment: "") }
                copy.trailingComma = true
                copy.tail = "\n"
            }
        }
        return copy
    }

    private var positions: [Before] { elements.map { $0.before.position } }

    /// The place of the element at `index` when the places in use are `places`: the one that is there, or past the last one, the last one's. A single element on a line
    /// has nothing to say about what stands between two of them (`["a"]` has no space after a comma yet), so the second is set a space apart.
    private static func place(at index: Int, in places: [Before]) -> Before {
        if index < places.count { return places[index] }
        guard var last = places.last else { return Before(head: "", lines: [], indent: "    ", hasNewline: true) }
        if places.count == 1, !last.hasNewline, last.head.isEmpty { last.head = " " }
        return last
    }

    private mutating func relayout(keepingPositionsOf places: [Before]) {
        for index in elements.indices where index < places.count {
            // What travels is the comment lines above the element; where it stands is the place's.
            elements[index].before = Before(head: places[index].head, lines: elements[index].before.lines, indent: places[index].indent, hasNewline: places[index].hasNewline)
        }
    }
}
