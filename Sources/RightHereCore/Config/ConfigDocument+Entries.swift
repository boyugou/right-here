import Foundation

extension ConfigDocument {
    /// Where an entry of `[[table]]` is in the text: the lines of the entry itself, and the blank lines that follow it. A comment directly above its header (no
    /// blank line between) belongs to the entry and moves with it.
    struct EntrySlot {
        /// The first line: the comment above the header when there is one, else the header.
        var first: Int
        /// The last line that is not blank.
        var last: Int
        /// The last blank line after it, or `last` when none follows.
        var end: Int
    }

    /// Adds an entry to the array of tables `table` (`preset`, `app`, `new_file.template`, `agent.claude.variant`) at `position` (from 1; after the last one
    /// without a position). Every key the entry needs has to be among the fields: an entry the parser would leave out is refused.
    public func addingEntry(to table: String, fields: [(key: String, value: Value)], at position: Int? = nil) throws -> ConfigDocument {
        let segments = try Self.segments(table)
        let node = try Self.schemaNode(path: table, segments: segments)
        guard node.kind == .tableArray else { throw EditError.wrongKind(path: table, expected: "a list of entries, which is made with the entries of [[\(table)]]") }
        for field in fields {
            let path = "\(table).1.\(field.key)"
            let child = try Self.schemaNode(path: path, segments: try Self.segments(path))
            try Self.require(child, accepts: field.value, path: path)
        }
        let layout = try makeLayout()
        // A list written as a value (`preset = [{ ... }]`) is not extended by a `[[preset]]` below it: the TOML spec forbids it, and a parser that follows it refuses the file.
        if layout.outline.valueRanges[table] != nil { throw EditError.inlineTable(table) }
        let slots = layout.slots(of: table)
        let at = position ?? slots.count + 1
        guard (1...slots.count + 1).contains(at) else { throw EditError.outOfRange(path: table, position: at, count: slots.count) }
        var chunk = "[[\(table)]]\n"
        for field in fields { chunk += "\(field.key) = \(Self.render(field.value, like: nil))\n" }
        if at <= slots.count {
            // Before an entry (and its comment): a blank line after the new one keeps them apart, and one before it when the line above is text.
            let above = slots[at - 1].first - 1
            let apart = above >= 1 && !layout.isBlank(above) ? "\n" : ""
            return try checked(layout.inserting(apart + chunk + "\n", afterLine: above))
        }
        if let last = slots.last {
            // After the last entry, a blank line before the new one; what followed the last entry stays after the new one.
            return try checked(layout.inserting("\n" + chunk, afterLine: last.last))
        }
        // The first entry of its kind, at the end of the text.
        return try checked(layout.appending(entry: chunk))
    }

    /// Makes the table `path` of a table per id (`agent.lazygit`) at the end of the text, with all its fields at once: an agent that is not built in needs a name and a command, so it cannot
    /// be made by setting its keys one after the other (each step would be a config that does not read).
    public func addingTable(_ path: String, fields: [(key: String, value: Value)]) throws -> ConfigDocument {
        let segments = try Self.segments(path)
        let node = try Self.schemaNode(path: path, segments: segments)
        guard node.kind == .tableMap, segments.count == 2 else { throw EditError.wrongKind(path: path, expected: "a table per id, which is made with the fields it needs (`agent.<id>`)") }
        for field in fields {
            let childPath = "\(path).\(field.key)"
            let child = try Self.schemaNode(path: childPath, segments: try Self.segments(childPath))
            try Self.require(child, accepts: field.value, path: childPath)
        }
        let layout = try makeLayout()
        if layout.outline.lines[path] != nil { throw EditError.exists(path) }
        let body = fields.map { "\($0.key) = \(Self.render($0.value, like: nil))\n" }.joined()
        return try checked(layout.appending(table: path, line: body))
    }

    /// The ids of the tables of a table per id (`agent`) that the text writes, however they are written (`[agent.mine]`, `[[agent.mine.variant]]`, `agent.mine.command = ...`).
    public func tableIDs(of table: String) -> Set<String> {
        var ids = Set<String>()
        for path in TOMLOutline(text).lines.keys where path.hasPrefix(table + ".") {
            if let id = path.dropFirst(table.count + 1).split(separator: ".", omittingEmptySubsequences: false).first, !id.isEmpty { ids.insert(String(id)) }
        }
        return ids
    }

    /// Removes the table `path` of a table per id (`agent.lazygit`) with the tables below it (`[[agent.lazygit.variant]]`) and the comment directly above each header; what stands around it stays.
    public func removingTable(_ path: String) throws -> ConfigDocument {
        let segments = try Self.segments(path)
        let node = try Self.schemaNode(path: path, segments: segments)
        guard node.kind == .tableMap, segments.count == 2 else { throw EditError.wrongKind(path: path, expected: "a table per id, which is removed whole (`agent.<id>`)") }
        let layout = try makeLayout()
        guard layout.headerLine(of: path) != nil else {
            // Written as dotted keys or in an inline table: not something to cut out by lines.
            if layout.outline.valueRanges[path] != nil || layout.outline.lines.keys.contains(where: { $0.hasPrefix(path + ".") }) { throw EditError.inlineTable(path) }
            throw EditError.notFound(path)
        }
        // The header of the table and the headers of the tables below it, wherever in the text they are written.
        let headers = layout.outline.lines.filter { ($0.key == path || $0.key.hasPrefix(path + ".")) && layout.headerLines.contains($0.value) }.map(\.value)
        var regions: [ClosedRange<Int>] = []
        for header in headers {
            // What comes next starts at its comment lines, which are not this table's.
            let next = layout.headerLines.first { $0 > header }.map(layout.attachedStart(of:)) ?? layout.lineCount + 1
            // The table ends with its last key and its value, and the comment lines right after that (a setting that is commented out, `# args = ["--fast"]`); a comment block that stands
            // apart, after a blank line, is the person's note about something else. The blank lines after the table go with it.
            var last = header
            for candidate in (header + 1)..<max(next, header + 1) where !layout.isBlankOrComment(candidate) { last = candidate }
            while last + 1 < next, !layout.isBlank(last + 1), layout.isBlankOrComment(last + 1) { last += 1 }
            var end = last
            while end + 1 < next, layout.isBlank(end + 1) { end += 1 }
            // The blank lines above a table that ends the text are taken off below, after the cut.
            regions.append(layout.attachedStart(of: header)...end)
        }
        var kept: [UInt8] = []
        var line = 1
        for region in regions.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if region.lowerBound > line { kept += layout.bytes[layout.offset(ofLine: line)..<layout.offset(ofLine: region.lowerBound)] }
            line = max(line, region.upperBound + 1)
        }
        kept += layout.bytes[layout.offset(ofLine: line)...]
        var result = String(decoding: kept, as: UTF8.self)
        // The last thing in the text was a table, however many there were: the text does not end with the blank lines that stood above it.
        if regions.contains(where: { $0.upperBound >= layout.lineCount }) {
            while result.hasSuffix("\n\n") { result.removeLast() }
            if result == "\n" { result = "" }
        }
        return try checked(result)
    }

    /// Removes the entry at `position` (from 1) with the comment directly above it.
    public func removingEntry(at position: Int, from table: String) throws -> ConfigDocument {
        let slots = try entrySlots(of: table)
        guard (1...max(slots.count, 1)).contains(position), position <= slots.count else {
            throw EditError.outOfRange(path: table, position: position, count: slots.count)
        }
        let layout = try makeLayout()
        let slot = slots[position - 1]
        var first = slot.first
        // The last thing in the text takes the blank lines above it with it, so that the text does not end with them.
        if slot.end >= layout.lineCount {
            while first > 1, layout.isBlank(first - 1) { first -= 1 }
        }
        return try checked(layout.removingLines(first...slot.end))
    }

    /// Moves the entry at `from` (from 1) so that it is at `to`: the entries change places, and what stands between them stays.
    public func movingEntry(from: Int, to: Int, in table: String) throws -> ConfigDocument {
        let slots = try entrySlots(of: table)
        for position in [from, to] where !(1...max(slots.count, 1)).contains(position) || position > slots.count {
            throw EditError.outOfRange(path: table, position: position, count: slots.count)
        }
        guard from != to else { return self }
        let layout = try makeLayout()
        var order = Array(1...slots.count)
        order.insert(order.remove(at: from - 1), at: to - 1)
        // What each place holds: the lines of the entry, then the blank lines of the place.
        func lines(_ range: ClosedRange<Int>) -> String {
            (range.lowerBound...range.upperBound).map { layout.text(ofLine: $0) + "\n" }.joined()
        }
        var result = layout.bytes
        for place in stride(from: slots.count, through: 1, by: -1) {
            let into = slots[place - 1]
            let entry = slots[order[place - 1] - 1]
            var chunk = lines(entry.first...entry.last)
            if into.end > into.last { chunk += lines((into.last + 1)...into.end) }
            let range = layout.offset(ofLine: into.first)..<layout.endOffset(ofLine: into.end)
            result.replaceSubrange(range, with: Array(chunk.utf8))
        }
        return try checked(String(decoding: result, as: UTF8.self))
    }

    private func entrySlots(of table: String) throws -> [EntrySlot] {
        let segments = try Self.segments(table)
        let node = try Self.schemaNode(path: table, segments: segments)
        guard node.kind == .tableArray else { throw EditError.wrongKind(path: table, expected: "a list of entries") }
        let slots = try makeLayout().slots(of: table)
        guard !slots.isEmpty else { throw EditError.notFound(table) }
        return slots
    }
}

extension ConfigDocument.Layout {
    /// The first line of what belongs to a header: the comment lines directly above it, with no blank line between.
    func attachedStart(of header: Int) -> Int {
        var first = header
        while first > 1, !insideValue.contains(first - 1), text(ofLine: first - 1).trimmingCharacters(in: .whitespaces).hasPrefix("#") { first -= 1 }
        return first
    }

    /// The slots of the entries of `[[table]]`, in the order they are written.
    func slots(of table: String) -> [ConfigDocument.EntrySlot] {
        var slots: [ConfigDocument.EntrySlot] = []
        var position = 1
        while let header = headerLine(of: "\(table).\(position)") {
            // The tables below this entry (`[agent.claude.variant.1.x]`) are part of it.
            let below = outline.lines.filter { $0.key.hasPrefix("\(table).\(position).") }
            // What comes next starts at its comment lines, which are not this entry's.
            let next = headerLines.first { $0 > header && !below.values.contains($0) }.map(attachedStart(of:)) ?? lineCount + 1
            // The entry ends with its last key and its value (a value may run over several lines). A comment block that stands apart after it, with a blank line between, is the
            // person's note about what follows or about nothing, and neither moves nor goes with the entry; the blank lines right after the entry do.
            var last = header
            for (path, line) in below {
                last = max(last, line)
                if let range = outline.valueRanges[path], !range.isEmpty { last = max(last, self.line(atOffset: range.upperBound - 1)) }
            }
            var end = last
            while end + 1 < next, isBlank(end + 1) { end += 1 }
            slots.append(ConfigDocument.EntrySlot(first: attachedStart(of: header), last: last, end: end))
            position += 1
        }
        return slots
    }

    /// The first entry of its kind: at the end of the text, after a blank line.
    func appending(entry: String) -> String {
        var out = bytes
        if let last = out.last, last != UInt8(ascii: "\n") { out.append(UInt8(ascii: "\n")) }
        if !out.isEmpty, !(lineCount >= 1 && isBlank(lineCount) && bytes.last == UInt8(ascii: "\n")) { out.append(UInt8(ascii: "\n")) }
        out += Array(entry.utf8)
        return String(decoding: out, as: UTF8.self)
    }
}
