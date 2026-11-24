import Foundation

/// How often and how recently each path was opened from the bar.
public struct UsageHistory: Sendable, Codable, Equatable {
    public struct Entry: Sendable, Codable, Equatable {
        public var count: Int
        public var lastUsed: Date
    }

    public private(set) var entries: [String: Entry] = [:]

    public init() {}

    public mutating func record(path: String, at date: Date) {
        var entry = entries[path] ?? Entry(count: 0, lastUsed: date)
        entry.count += 1
        entry.lastUsed = date
        entries[path] = entry
    }

    /// Grows with use and halves every 30 days without it, so an old habit fades instead of winning forever.
    public func bonus(path: String, now: Date) -> Int {
        guard let entry = entries[path] else { return 0 }
        let days = max(0, now.timeIntervalSince(entry.lastUsed)) / 86_400
        let decay = pow(0.5, days / 30)
        return Int(min(250, 60 * log2(Double(entry.count) + 1)) * decay)
    }

    public func recentPaths(limit: Int, now: Date) -> [String] {
        entries.keys
            .sorted { bonus(path: $0, now: now) > bonus(path: $1, now: now) }
            .prefix(limit)
            .map { $0 }
    }
}

public struct ScoredItem: Sendable, Hashable {
    public let item: SearchItem
    public let score: Int
}

public enum Ranker {
    public static func rank(query: String, items: [SearchItem], usage: UsageHistory, now: Date) -> [ScoredItem] {
        let normalized = FuzzyMatcher.normalize(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !normalized.isEmpty else { return [] }

        var scored: [ScoredItem] = []
        var seen = Set<String>()
        for item in items where seen.insert(item.path).inserted {
            guard let best = matchScore(of: item, query: normalized) else { continue }
            scored.append(ScoredItem(item: item, score: best + kindBonus(item.kind) + usage.bonus(path: item.path, now: now)))
        }
        return scored.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            // Same name twice, as with one AUTOMATICA per academic year: the folder touched last comes first.
            let lhsDate = lhs.item.modified ?? .distantPast
            let rhsDate = rhs.item.modified ?? .distantPast
            if lhsDate != rhsDate { return lhsDate > rhsDate }
            return lhs.item.path < rhs.item.path
        }
    }

    /// There are hundreds of settings, so a loose match on their names would crowd out what you were looking for.
    private static let minimumSettingNameScore = 450
    /// Keeps an entry called "Display", inside Accessibility, from beating the Displays page when you type "display".
    private static let maximumEntryScore = 880
    /// Below a real name match, but high enough to count as an answer: "monitor" should lead to Displays.
    private static let keywordScore = 520
    private static let minimumKeywordLength = 3

    private static func matchScore(of item: SearchItem, query: String) -> Int? {
        let isSetting = item.kind == .setting || item.kind == .settingsPane
        let nameScore = item.searchKeys
            .compactMap { FuzzyMatcher.score(query: query, candidate: $0) }
            .max()
            .flatMap { !isSetting || $0 >= minimumSettingNameScore ? $0 : nil }
        if let nameScore {
            return item.kind == .setting ? min(nameScore, maximumEntryScore) : nameScore
        }
        return query.count >= minimumKeywordLength && item.keywords.contains(query) ? keywordScore : nil
    }

    private static func kindBonus(_ kind: SearchItem.Kind) -> Int {
        switch kind {
        case .project: 60
        case .settingsPane: 50
        case .app: 40
        case .setting: 10
        case .folder: 0
        case .file: -80
        }
    }
}

public enum ResultRow: Sendable, Hashable, Identifiable {
    case item(SearchItem)
    case claude(prompt: String, incognito: Bool)

    public var id: String {
        switch self {
        case .item(let item): "item:\(item.path)"
        case .claude(_, let incognito): "claude:\(incognito)"
        }
    }
}

public struct ResultSection: Sendable, Hashable, Identifiable {
    public let title: String
    public let rows: [ResultRow]

    public var id: String { title }

    public init(title: String, rows: [ResultRow]) {
        self.title = title
        self.rows = rows
    }
}

public enum QueryIntent {
    private static let questionStarters: Set<String> = [
        "what", "how", "why", "when", "where", "who", "which", "can", "could", "should", "explain", "write", "summarize", "translate",
    ]

    /// Whether the text reads like something to ask rather than a name to find.
    public static func looksLikeQuestion(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("?") { return true }
        let words = FuzzyMatcher.normalize(trimmed).split(whereSeparator: \.isWhitespace).map(String.init)
        if words.count >= 5 { return true }
        guard words.count >= 2, let first = words.first else { return false }
        return questionStarters.contains(first)
    }
}

public enum ResultComposer {
    /// Below this, a match is too loose for Claude to be pushed under it.
    private static let strongMatchScore = 500

    public static func compose(query: String, ranked: [ScoredItem]) -> [ResultSection] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let groups: [(title: String, kinds: Set<SearchItem.Kind>, limit: Int)] = [
            ("App", [.app], 4),
            ("Settings", [.settingsPane, .setting], 5),
            ("Projects & Folders", [.project, .folder], 8),
            ("Files", [.file], 5),
        ]
        var sections: [(best: Int, section: ResultSection)] = []
        for group in groups {
            let matches = ranked.filter { group.kinds.contains($0.item.kind) }.prefix(group.limit)
            guard let best = matches.first?.score else { continue }
            sections.append((best, ResultSection(title: group.title, rows: matches.map { .item($0.item) })))
        }
        let local = sections.sorted { $0.best > $1.best }.map(\.section)

        let claude = ResultSection(title: "Claude", rows: [
            .claude(prompt: trimmed, incognito: false),
            .claude(prompt: trimmed, incognito: true),
        ])
        let hasStrongMatch = (ranked.first?.score ?? 0) >= strongMatchScore
        if QueryIntent.looksLikeQuestion(trimmed) || !hasStrongMatch {
            return [claude] + local
        }
        return local + [claude]
    }
}
