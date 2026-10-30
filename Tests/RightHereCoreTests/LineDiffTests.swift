import Foundation
import Testing
@testable import RightHereCore

@Suite("LineDiff: a unified diff of two config texts")
struct LineDiffTests {
    @Test func equalTextsHaveNoDifference() {
        #expect(LineDiff.unified(from: "a\nb\n", to: "a\nb\n").isEmpty)
        #expect(LineDiff.unified(from: "", to: "").isEmpty)
    }

    @Test func aChangedLineIsShownWithItsNeighbours() {
        let old = "1\n2\n3\n4\n5\n6\n7\n"
        let new = "1\n2\n3\nfour\n5\n6\n7\n"
        #expect(LineDiff.unified(from: old, to: new) == ["@@ -2,5 +2,5 @@", " 2", " 3", "-4", "+four", " 5", " 6"])
        #expect(LineDiff.unified(from: old, to: new, context: 0) == ["@@ -4,1 +4,1 @@", "-4", "+four"])
    }

    @Test func anAddedAndARemovedLineAreCountedWhereTheyAre() {
        #expect(LineDiff.unified(from: "a\nb\n", to: "a\nx\nb\n") == ["@@ -1,2 +1,3 @@", " a", "+x", " b"])
        #expect(LineDiff.unified(from: "a\nx\nb\n", to: "a\nb\n") == ["@@ -1,3 +1,2 @@", " a", "-x", " b"])
        #expect(LineDiff.unified(from: "", to: "a\nb\n") == ["@@ -0,0 +1,2 @@", "+a", "+b"])
        #expect(LineDiff.unified(from: "a\nb\n", to: "") == ["@@ -1,2 +0,0 @@", "-a", "-b"])
    }

    @Test func farApartChangesAreTwoHunksAndNearOnesAreOne() {
        let old = (1...20).map(String.init).joined(separator: "\n") + "\n"
        var far = (1...20).map(String.init)
        far[1] = "two"
        far[17] = "eighteen"
        let hunks = LineDiff.unified(from: old, to: far.joined(separator: "\n") + "\n").filter { $0.hasPrefix("@@") }
        #expect(hunks == ["@@ -1,4 +1,4 @@", "@@ -16,5 +16,5 @@"])
        var near = (1...20).map(String.init)
        near[1] = "two"
        near[5] = "six"
        #expect(LineDiff.unified(from: old, to: near.joined(separator: "\n") + "\n").filter { $0.hasPrefix("@@") }.count == 1)
    }

    @Test func aDifferenceOnlyInTheFinalLineBreakIsSaid() {
        #expect(LineDiff.unified(from: "a\nb", to: "a\nb\n") == ["\\ only the line break at the end of the text differs"])
    }

    @Test func theDiffAppliedToTheOldTextGivesTheNewOne() {
        // The numbers in the headers and the lines of each hunk are checked by doing what the diff says.
        var seed: UInt64 = 42
        func next(_ bound: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 33) % UInt64(bound))
        }
        for round in 0..<300 {
            let pool = ["a", "b", "c", "d", "e", "# note", "", "x = 1"]
            let old = (0..<next(14)).map { _ in pool[next(pool.count)] }
            var new = old
            for _ in 0..<next(5) {
                switch next(3) {
                case 0 where !new.isEmpty: new.remove(at: next(new.count))
                case 1: new.insert(pool[next(pool.count)], at: next(new.count + 1))
                default: if !new.isEmpty { new[next(new.count)] = pool[next(pool.count)] }
                }
            }
            let oldText = old.map { $0 + "\n" }.joined(), newText = new.map { $0 + "\n" }.joined()
            let diff = LineDiff.unified(from: oldText, to: newText, context: next(4))
            #expect(Self.apply(diff, to: old) == new, "round \(round): \(old) -> \(new)\n\(diff.joined(separator: "\n"))")
        }
    }

    @Test func aHugeMiddleIsShownWholeInsteadOfTakingForEver() {
        let old = (0..<3000).map { "old \($0)" }.joined(separator: "\n") + "\n"
        let new = (0..<3000).map { "new \($0)" }.joined(separator: "\n") + "\n"
        let diff = LineDiff.unified(from: old, to: new, context: 0)
        #expect(diff.count == 6001 && diff[0] == "@@ -1,3000 +1,3000 @@")
    }

    /// Applies a unified diff to the lines of the old text.
    private static func apply(_ diff: [String], to old: [String]) -> [String] {
        var result: [String] = []
        var cursor = 0
        for line in diff {
            if line.hasPrefix("@@") {
                let header = line.split(separator: " ")
                let oldPart = header[1].dropFirst().split(separator: ",")
                let start = Int(oldPart[0]) ?? 0
                let count = Int(oldPart[1]) ?? 0
                // A hunk with no old lines starts after the line its number names.
                let first = count == 0 ? start : start - 1
                while cursor < first { result.append(old[cursor]); cursor += 1 }
            } else if line.hasPrefix("+") {
                result.append(String(line.dropFirst()))
            } else if line.hasPrefix("-") {
                cursor += 1
            } else if line.hasPrefix(" ") {
                result.append(old[cursor])
                cursor += 1
            }
        }
        while cursor < old.count { result.append(old[cursor]); cursor += 1 }
        return result
    }

    @Test func aLineThatTurnsTheTextAroundOrDrawsNothingIsShownAsEscapes() {
        let lines = LineDiff.unified(from: "[agent.claude]\ncommand = \"claude\"\n", to: "[agent.claude]\ncommand = \"claude\u{202E} x\u{200B}\u{E0041}\"\n")
        #expect(!lines.joined().unicodeScalars.contains { [0x202E, 0x200B, 0xE0041].contains($0.value) }, "\(lines)")
        #expect(lines.contains("+command = \"claude\\u202e x\\u200b\\udb40\\udc41\""), "\(lines)")
        #expect(LineDiff.unified(from: "a\n\tb\n", to: "a\n\tc\n").contains("+\tc"), "a tab is a tab")
    }
}
