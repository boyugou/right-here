import Foundation

extension ConfigDocument {
    /// A config text read for editing: its bytes, where each line starts, and where the outline found each table, key and value.
    struct Layout {
        let bytes: [UInt8]
        let outline: TOMLOutline
        /// The offset at which each line starts; a final line break does not start another line.
        let starts: [Int]
        /// The lines of `[table]` and `[[entry]]` headers, in order.
        let headerLines: [Int]
        /// The lines that are the inside of a value written across lines (a `\"\"\"` string, a list): a line there is part of the value, whatever it starts with, and is never a comment or a blank line.
        let insideValue: Set<Int>

        /// A text that already has an error is not edited: the edit would be made on something that cannot be read.
        init(_ text: String, validation: Validation) throws {
            if let error = validation.errors(text).first { throw EditError.unreadable(error) }
            bytes = Array(text.utf8)
            outline = TOMLOutline(text)
            var found = [0]
            for (offset, byte) in bytes.enumerated() where byte == UInt8(ascii: "\n") { found.append(offset + 1) }
            if found.count > 1, found.last == bytes.count { found.removeLast() }
            starts = found
            var headers = Set<Int>()
            for (_, line) in outline.lines where line >= 1 && line <= found.count {
                let first = bytes[found[line - 1]...].first { $0 != UInt8(ascii: " ") && $0 != UInt8(ascii: "\t") }
                if first == UInt8(ascii: "[") { headers.insert(line) }
            }
            headerLines = headers.sorted()
            var inside = Set<Int>()
            func line(atOffset offset: Int) -> Int {
                var low = 0, high = found.count - 1
                while low < high {
                    let middle = (low + high + 1) / 2
                    if found[middle] <= offset { low = middle } else { high = middle - 1 }
                }
                return low + 1
            }
            for (_, range) in outline.valueRanges where !range.isEmpty {
                let first = line(atOffset: range.lowerBound), last = line(atOffset: range.upperBound - 1)
                if last > first { inside.formUnion((first + 1)...last) }
            }
            insideValue = inside
        }

        var lineCount: Int { starts.count }

        /// The offset at which a line (from 1) starts; past the last line, the end of the text.
        func offset(ofLine line: Int) -> Int {
            line >= 1 && line <= starts.count ? starts[line - 1] : bytes.count
        }

        /// The offset just after a line and its line break.
        func endOffset(ofLine line: Int) -> Int {
            offset(ofLine: line + 1)
        }

        func line(atOffset offset: Int) -> Int {
            var low = 0, high = starts.count - 1
            while low < high {
                let middle = (low + high + 1) / 2
                if starts[middle] <= offset { low = middle } else { high = middle - 1 }
            }
            return low + 1
        }

        func text(ofLine line: Int) -> String {
            guard line >= 1 && line <= starts.count else { return "" }
            var end = endOffset(ofLine: line)
            while end > starts[line - 1], bytes[end - 1] == UInt8(ascii: "\n") || bytes[end - 1] == UInt8(ascii: "\r") { end -= 1 }
            return String(decoding: bytes[starts[line - 1]..<end], as: UTF8.self)
        }

        func isBlankOrComment(_ line: Int) -> Bool {
            if insideValue.contains(line) { return false }
            let trimmed = text(ofLine: line).trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty || trimmed.hasPrefix("#")
        }

        func isBlank(_ line: Int) -> Bool {
            if insideValue.contains(line) { return false }
            return text(ofLine: line).trimmingCharacters(in: .whitespaces).isEmpty
        }

        /// The line of the `[table]` or `[[entry]]` header at this path, when there is one.
        func headerLine(of path: String) -> Int? {
            guard let line = outline.lines[path], headerLines.contains(line) else { return nil }
            return line
        }

        /// The first line after a header that is a header too, or the line after the last.
        func endOfTable(startingAt header: Int) -> Int {
            headerLines.first { $0 > header } ?? lineCount + 1
        }

        /// Whether some part of this path is the value of a key: the key is written inside an inline table.
        func isInsideInlineTable(_ segments: [String]) -> Bool {
            guard segments.count > 1 else { return false }
            return (1..<segments.count).contains { outline.valueRanges[segments[0..<$0].joined(separator: ".")] != nil }
        }

        // MARK: Building the new text

        private func text(_ bytes: [UInt8]) -> String { String(decoding: bytes, as: UTF8.self) }

        func replacing(_ range: Range<Int>, with replacement: String) -> String {
            text(Array(bytes[0..<range.lowerBound]) + Array(replacement.utf8) + Array(bytes[range.upperBound...]))
        }

        func removingLines(_ lines: ClosedRange<Int>) -> String {
            text(Array(bytes[0..<offset(ofLine: lines.lowerBound)]) + Array(bytes[endOffset(ofLine: lines.upperBound)...]))
        }

        /// Puts whole lines after a line (0 for the very start of the text); a text without a final line break gets one first.
        func inserting(_ lines: String, afterLine line: Int) -> String {
            let at = line == 0 ? 0 : endOffset(ofLine: line)
            var inserted = Array(lines.utf8)
            if at == bytes.count, at > 0, bytes[at - 1] != UInt8(ascii: "\n") { inserted.insert(UInt8(ascii: "\n"), at: 0) }
            return text(Array(bytes[0..<at]) + inserted + Array(bytes[at...]))
        }

        /// A key that is not in the text: at the end of its table, which is made at the end of the text when there is none.
        func insertingKey(_ segments: [String], rendered: String, path: String) throws -> String {
            let line = "\(segments[segments.count - 1]) = \(rendered)\n"
            let tablePath = segments.dropLast().joined(separator: ".")
            if tablePath.isEmpty {
                // At the top, below the other keys that are there and above the first table.
                var last = 0
                var candidate = (headerLines.first ?? lineCount + 1) - 1
                while candidate >= 1 {
                    if !isBlankOrComment(candidate) { last = candidate; break }
                    candidate -= 1
                }
                return inserting(last == 0 ? line + "\n" : line, afterLine: last)
            }
            if let header = headerLine(of: tablePath) {
                var last = header
                var candidate = endOfTable(startingAt: header) - 1
                while candidate > header {
                    if !isBlankOrComment(candidate) { last = candidate; break }
                    candidate -= 1
                }
                return inserting(line, afterLine: last)
            }
            if outline.valueRanges[tablePath] != nil || isInsideInlineTable(Array(segments.dropLast())) {
                throw EditError.inlineTable(tablePath)
            }
            // An entry (`preset.2`) is not made by writing a key into it.
            if segments.dropLast().contains(where: { Int($0) != nil }) { throw EditError.notFound(tablePath) }
            // A table that dotted keys define at the top (`copy_path.title = "x"`) cannot have a header as well: the new key is one more dotted key, after the last of them.
            let prefix = tablePath + "."
            let firstHeader = headerLines.first ?? lineCount + 1
            let dotted = outline.valueRanges.filter { $0.key.hasPrefix(prefix) && !$0.value.isEmpty }.map { self.line(atOffset: $0.value.upperBound - 1) }.filter { $0 < firstHeader }
            if let last = dotted.max() { return inserting("\(segments.joined(separator: ".")) = \(rendered)\n", afterLine: last) }
            return appending(table: tablePath, line: line)
        }

        func appending(table path: String, line: String) -> String {
            var out = bytes
            if let last = out.last, last != UInt8(ascii: "\n") { out.append(UInt8(ascii: "\n")) }
            if !out.isEmpty, !(lineCount >= 1 && isBlank(lineCount) && bytes.last == UInt8(ascii: "\n")) { out.append(UInt8(ascii: "\n")) }
            out += Array("[\(path)]\n\(line)".utf8)
            return text(out)
        }
    }
}
