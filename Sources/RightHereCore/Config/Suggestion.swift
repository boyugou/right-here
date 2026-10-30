import Foundation

/// A suggested fix for a diagnostic: prose for people and the replacement text for tools.
struct Hint {
    var text: String
    /// The text to put in place of the wrong one, when there is one (a key that belongs elsewhere has none).
    var replacement: String?
}

enum Suggestion {
    static func didYouMean(_ word: String, in candidates: [String]) -> Hint? {
        closest(to: word, in: candidates).map { Hint(text: "did you mean \"\($0)\"?", replacement: $0) }
    }

    /// Like `didYouMean` for something that has an id and a name (an app, an agent): a word that is the name, whatever the case
    /// ("Visual Studio Code"), or close to it, leads to the id.
    static func didYouMean(_ word: String, in things: [(id: String, name: String)]) -> Hint? {
        let lowered = word.lowercased()
        if let exact = things.first(where: { $0.id == lowered || $0.name.lowercased() == lowered }), exact.id != word {
            return Hint(text: "did you mean \"\(exact.id)\"?", replacement: exact.id)
        }
        let spellings = things.flatMap { [($0.id, $0.id), ($0.name.lowercased(), $0.id)] }
        guard let best = closest(to: lowered, in: spellings.map(\.0)), let id = spellings.first(where: { $0.0 == best })?.1 else { return nil }
        return Hint(text: "did you mean \"\(id)\"?", replacement: id)
    }

    /// The closest candidate within a small edit distance, if any.
    static func closest(to word: String, in candidates: [String]) -> String? {
        let best = candidates.map { ($0, distance(word, $0)) }.min { $0.1 < $1.1 }
        guard let (candidate, score) = best, score <= max(2, word.count / 3) else { return nil }
        return candidate
    }

    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }
}
