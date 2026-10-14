import Foundation

enum WordFeedback {
    enum Vote: Int { case down = -1, up = 1 }

    private static let key = "wordFeedback.v1"
    private static let group = "group.com.kaps.pdfpipe"

    static func load(from defaults: UserDefaults? = UserDefaults(suiteName: group)) -> [String: Int] {
        guard let stored = defaults?.dictionary(forKey: key) else { return [:] }
        return stored.compactMapValues { value in
            guard let number = value as? Int, number == -1 || number == 1 else { return nil }
            return number
        }
    }

    static func set(_ vote: Vote?, for word: RankedWord,
                    in defaults: UserDefaults? = UserDefaults(suiteName: group)) throws -> [String: Int] {
        guard let defaults else { throw PipeError.message("Cannot save word preferences in shared storage.") }
        var votes = load(from: defaults)
        votes[word.id] = vote?.rawValue
        defaults.set(votes, forKey: key)
        return votes
    }

    static func remove(_ id: String,
                       from defaults: UserDefaults? = UserDefaults(suiteName: group)) throws -> [String: Int] {
        guard let defaults else { throw PipeError.message("Cannot save word preferences in shared storage.") }
        var votes = load(from: defaults)
        votes.removeValue(forKey: id)
        defaults.set(votes, forKey: key)
        return votes
    }

    static func clear(in defaults: UserDefaults? = UserDefaults(suiteName: group)) throws {
        guard let defaults else { throw PipeError.message("Cannot save word preferences in shared storage.") }
        defaults.removeObject(forKey: key)
    }

    /// A preference can move a document term, but cannot invent one or dominate layout evidence.
    static func suggestions(from words: [RankedWord], votes: [String: Int]) -> [RankedWord] {
        words.enumerated().map { index, word in
            (index: index, word: RankedWord(text: word.text,
                score: word.score + 0.55 * Double(votes[word.id] ?? 0)))
        }.sorted { lhs, rhs in
            if lhs.word.score != rhs.word.score { return lhs.word.score > rhs.word.score }
            return lhs.index < rhs.index
        }.prefix(30).map(\.word)
    }
}
