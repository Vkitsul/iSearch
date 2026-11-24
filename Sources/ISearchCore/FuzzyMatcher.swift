import Foundation

/// Scores how well a query matches a name. Higher is better; `nil` means no match.
public enum FuzzyMatcher {
    /// Case- and accent-insensitive form, so "perché" matches "PERCHE".
    public static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// Both arguments must already be normalized.
    public static func score(query: String, candidate: String) -> Int? {
        guard !query.isEmpty else { return nil }
        if let whole = scoreSingle(query: query, candidate: candidate) { return whole }

        // "reti logiche" should still find "LOGICHE-RETI": every word has to match on its own.
        let tokens = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard tokens.count > 1 else { return nil }
        var lowest = Int.max
        for token in tokens {
            guard let tokenScore = scoreSingle(query: token, candidate: candidate), tokenScore >= substringBase - 100 else {
                return nil
            }
            lowest = min(lowest, tokenScore)
        }
        return lowest - 40
    }

    private static let substringBase = 600

    private static func scoreSingle(query: String, candidate: String) -> Int? {
        if candidate == query { return 1000 }

        let extraLength = max(0, candidate.count - query.count)
        if candidate.hasPrefix(query) { return 900 - min(extraLength, 100) }

        let words = candidate.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        if words.contains(where: { $0 == query }) { return 800 - min(extraLength, 50) }
        if words.contains(where: { $0.hasPrefix(query) }) { return 760 - min(extraLength, 50) }

        if query.count >= 2, words.count >= query.count {
            let initials = String(words.compactMap(\.first))
            if initials.hasPrefix(query) { return 720 }
        }
        if candidate.contains(query) { return substringBase - min(extraLength, 100) }
        return subsequenceScore(query: query, candidate: candidate)
    }

    /// Characters in order with gaps ("elttrn" → "elettronica"). Widely scattered hits are noise, so they are rejected.
    private static func subsequenceScore(query: String, candidate: String) -> Int? {
        guard query.count >= 3 else { return nil }
        var pending = Array(query)[...]
        var firstHit: Int?
        var lastHit = 0
        for (position, character) in candidate.enumerated() where character == pending.first {
            if firstHit == nil { firstHit = position }
            lastHit = position
            pending.removeFirst()
            if pending.isEmpty { break }
        }
        guard pending.isEmpty, let firstHit else { return nil }
        let span = lastHit - firstHit + 1
        guard span <= query.count * 2 else { return nil }
        return 150 + 200 * query.count / span
    }
}
