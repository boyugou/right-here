import Foundation

/// The lines that differ between two texts, as a unified diff: what `rh config set --dry-run` shows an agent and what a window shows before it applies a change.
public enum LineDiff {
    private enum Kind { case same, removed, added }

    private struct Row {
        var kind: Kind
        var text: String
    }

    /// Hunks of the lines that changed with `context` lines around them, each under `@@ -first,count +first,count @@`; none when the texts are the same.
    public static func unified(from old: String, to new: String, context: Int = 2) -> [String] {
        guard old != new else { return [] }
        let rows = difference(lines(old), lines(new))
        guard rows.contains(where: { $0.kind != .same }) else { return ["\\ only the line break at the end of the text differs"] }
        var changed: [Int] = []
        for (index, row) in rows.enumerated() where row.kind != .same { changed.append(index) }
        // The runs of rows that one hunk shows.
        var ranges: [ClosedRange<Int>] = []
        for index in changed {
            let low = max(0, index - context), high = min(rows.count - 1, index + context)
            if let last = ranges.last, low <= last.upperBound + 1 {
                ranges[ranges.count - 1] = last.lowerBound...max(last.upperBound, high)
            } else {
                ranges.append(low...high)
            }
        }
        // The line each row has in the old and in the new text.
        var oldNumber = [Int](repeating: 0, count: rows.count + 1)
        var newNumber = [Int](repeating: 0, count: rows.count + 1)
        var o = 1, n = 1
        for (index, row) in rows.enumerated() {
            oldNumber[index] = o
            newNumber[index] = n
            if row.kind != .added { o += 1 }
            if row.kind != .removed { n += 1 }
        }
        var out: [String] = []
        for range in ranges {
            let slice = rows[range]
            let oldCount = slice.filter { $0.kind != .added }.count
            let newCount = slice.filter { $0.kind != .removed }.count
            out.append("@@ -\(oldCount == 0 ? oldNumber[range.lowerBound] - 1 : oldNumber[range.lowerBound]),\(oldCount) +\(newCount == 0 ? newNumber[range.lowerBound] - 1 : newNumber[range.lowerBound]),\(newCount) @@")
            for row in slice {
                switch row.kind {
                case .same: out.append(" " + Self.shown(row.text))
                case .removed: out.append("-" + Self.shown(row.text))
                case .added: out.append("+" + Self.shown(row.text))
                }
            }
        }
        return out
    }

    /// A line as it is read on a card or a terminal: a character that draws nothing or turns the text around is an escape (a tab stays a tab).
    private static func shown(_ line: String) -> String {
        line.escapingControlCharacters(keeping: ["\t"])
    }

    private static func lines(_ text: String) -> [String] {
        var parts = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if parts.last == "" { parts.removeLast() }
        return parts
    }

    /// The lines in order with what became of each: the longest run they have in common is kept. What the two share at the start and at the end is taken off
    /// first, which is nearly all of a config; a middle too large to compare is shown as removed and added whole.
    private static func difference(_ old: [String], _ new: [String]) -> [Row] {
        var start = 0
        while start < old.count, start < new.count, old[start] == new[start] { start += 1 }
        var end = 0
        while end < old.count - start, end < new.count - start, old[old.count - 1 - end] == new[new.count - 1 - end] { end += 1 }
        let a = Array(old[start..<(old.count - end)]), b = Array(new[start..<(new.count - end)])
        var rows = old[..<start].map { Row(kind: .same, text: $0) }
        if a.count * b.count > 4_000_000 {
            rows += a.map { Row(kind: .removed, text: $0) } + b.map { Row(kind: .added, text: $0) }
        } else {
            // length[i][j]: the longest run that a[i...] and b[j...] have in common.
            let width = b.count + 1
            var length = [Int32](repeating: 0, count: (a.count + 1) * width)
            for i in stride(from: a.count - 1, through: 0, by: -1) {
                for j in stride(from: b.count - 1, through: 0, by: -1) {
                    length[i * width + j] = a[i] == b[j] ? length[(i + 1) * width + j + 1] + 1 : max(length[(i + 1) * width + j], length[i * width + j + 1])
                }
            }
            var i = 0, j = 0
            while i < a.count || j < b.count {
                if i < a.count, j < b.count, a[i] == b[j] {
                    rows.append(Row(kind: .same, text: a[i]))
                    i += 1
                    j += 1
                } else if j == b.count || (i < a.count && length[(i + 1) * width + j] >= length[i * width + j + 1]) {
                    rows.append(Row(kind: .removed, text: a[i]))
                    i += 1
                } else {
                    rows.append(Row(kind: .added, text: b[j]))
                    j += 1
                }
            }
        }
        rows += old[(old.count - end)...].map { Row(kind: .same, text: $0) }
        return rows
    }
}
