import Foundation
import Testing
@testable import ISearchCore

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private let home = "/Users/test"

private func folder(_ path: String, modified: Date? = nil, kind: SearchItem.Kind = .project) -> SearchItem {
    SearchItem(path: path, kind: kind, title: (path as NSString).lastPathComponent, modified: modified)
}

@Suite struct FuzzyMatching {
    private func score(_ query: String, _ candidate: String) -> Int? {
        FuzzyMatcher.score(query: FuzzyMatcher.normalize(query), candidate: FuzzyMatcher.normalize(candidate))
    }

    @Test(arguments: [
        ("elettronica", "ELETTRONICA"),
        ("Automatica", "AUTOMATICA"),
        ("perche", "Perché"),
        ("reti", "RETI LOGICHE"),
        ("logiche reti", "RETI LOGICHE"),
        ("rl", "RETI LOGICHE"),
        ("elttrn", "ELETTRONICA"),
    ])
    func `finds the name`(query: String, candidate: String) {
        #expect(score(query, candidate) != nil)
    }

    @Test(arguments: [("xyz", "ELETTRONICA"), ("elettronica", "Elettro"), ("ac", "Automatica Progetto Lungo")])
    func `rejects what does not match`(query: String, candidate: String) {
        #expect(score(query, candidate) == nil)
    }

    @Test func `closer matches score higher`() throws {
        let exact = try #require(score("reti", "reti"))
        let prefix = try #require(score("reti", "reti logiche"))
        let word = try #require(score("reti", "esame reti"))
        let inside = try #require(score("reti", "segreti"))
        #expect(exact > prefix)
        #expect(prefix > word)
        #expect(word > inside)
    }
}

@Suite struct Ranking {
    @Test func `the same folder name puts the most recently changed first`() {
        let ranked = Ranker.rank(
            query: "Automatica",
            items: [
                folder("/Users/test/Desktop/2024-2025/AUTOMATICA", modified: now.addingTimeInterval(-90 * 86_400)),
                folder("/Users/test/Desktop/2025-2026/AUTOMATICA", modified: now.addingTimeInterval(-86_400)),
            ],
            usage: UsageHistory(),
            now: now
        )
        #expect(ranked.first?.item.path == "/Users/test/Desktop/2025-2026/AUTOMATICA")
    }

    @Test func `a project beats a Spotlight folder and a file with the same name`() {
        let ranked = Ranker.rank(
            query: "elettronica",
            items: [
                folder("/Users/test/Downloads/elettronica", kind: .file),
                folder("/Users/test/Downloads/old/elettronica", kind: .folder),
                folder("/Users/test/Desktop/ELETTRONICA"),
            ],
            usage: UsageHistory(),
            now: now
        )
        #expect(ranked.map(\.item.kind) == [.project, .folder, .file])
    }

    @Test func `an item found twice appears once`() {
        let item = folder("/Users/test/Desktop/ELETTRONICA")
        let ranked = Ranker.rank(query: "elettronica", items: [item, item], usage: UsageHistory(), now: now)
        #expect(ranked.count == 1)
    }

    @Test func `an app also matches by its other name`() {
        let settings = SearchItem(
            path: "/System/Applications/System Settings.app",
            kind: .app,
            title: "Impostazioni di Sistema",
            alternativeNames: ["System Settings"]
        )
        #expect(Ranker.rank(query: "system", items: [settings], usage: UsageHistory(), now: now).count == 1)
        #expect(Ranker.rank(query: "impostazioni", items: [settings], usage: UsageHistory(), now: now).count == 1)
    }

    @Test func `opening something often moves it up, and the effect fades`() {
        var usage = UsageHistory()
        let older = now.addingTimeInterval(-365 * 86_400)
        for _ in 0..<5 { usage.record(path: "/a", at: now) }
        for _ in 0..<5 { usage.record(path: "/b", at: older) }
        #expect(usage.bonus(path: "/a", now: now) > usage.bonus(path: "/b", now: now))
        #expect(usage.bonus(path: "/never", now: now) == 0)
        #expect(usage.recentPaths(limit: 1, now: now) == ["/a"])
    }
}

@Suite struct Composition {
    private func strong(_ path: String, kind: SearchItem.Kind = .project) -> ScoredItem {
        ScoredItem(item: folder(path, kind: kind), score: 1000)
    }

    @Test(arguments: ["how does a diode work", "why is the sky blue", "what is rust", "diode?", "one two three four five"])
    func `a question counts as one`(query: String) {
        #expect(QueryIntent.looksLikeQuestion(query))
    }

    @Test(arguments: ["Elettronica", "Automatica", "reti logiche", "how"])
    func `a name does not`(query: String) {
        #expect(!QueryIntent.looksLikeQuestion(query))
    }

    @Test func `Claude comes after a strong match on a name`() {
        let sections = ResultComposer.compose(query: "Elettronica", ranked: [strong("/x/ELETTRONICA")])
        #expect(sections.map(\.title) == ["Projects & Folders", "Claude"])
    }

    @Test func `Claude comes first on a question, even with matches`() {
        let sections = ResultComposer.compose(query: "how does elettronica work", ranked: [strong("/x/ELETTRONICA")])
        #expect(sections.first?.title == "Claude")
    }

    @Test func `Claude comes first when nothing matches`() {
        let sections = ResultComposer.compose(query: "qwerty", ranked: [])
        #expect(sections.map(\.title) == ["Claude"])
    }

    @Test func `both chat modes are always offered`() throws {
        let sections = ResultComposer.compose(query: "ciao", ranked: [])
        let rows = try #require(sections.first?.rows)
        #expect(rows == [.claude(prompt: "ciao", incognito: false), .claude(prompt: "ciao", incognito: true)])
    }

    @Test func `an empty query shows nothing`() {
        #expect(ResultComposer.compose(query: "   ", ranked: []).isEmpty)
    }
}

@Suite struct ClaudeLinks {
    @Test func `a normal chat opens in the desktop app with the prompt`() {
        #expect(ClaudeLink.chat(prompt: "ciao").absoluteString == "claude://claude.ai/new?surface=chat&q=ciao")
    }

    @Test func `an incognito chat goes through the web`() {
        #expect(ClaudeLink.incognitoChat(prompt: "ciao").absoluteString == "https://claude.ai/new?incognito&q=ciao")
    }

    @Test func `special characters survive the trip`() throws {
        let prompt = "2+2 = 4? sì & no #1"
        let url = ClaudeLink.chat(prompt: prompt)
        #expect(!url.absoluteString.contains("+"))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.first { $0.name == "q" }?.value == prompt)
    }

    @Test func `an empty prompt opens a blank chat`() {
        #expect(ClaudeLink.chat(prompt: "  ").absoluteString == "claude://claude.ai/new?surface=chat")
        #expect(ClaudeLink.webChat(prompt: "").absoluteString == "https://claude.ai/new")
    }

    @Test func `a very long prompt is cut to what the app accepts`() throws {
        let url = ClaudeLink.chat(prompt: String(repeating: "a", count: 20_000))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.first { $0.name == "q" }?.value?.count == ClaudeLink.maxPromptLength)
    }

    @Test func `a Claude Code session carries the folder, spaces included`() throws {
        let url = ClaudeLink.codeSession(folder: "/Users/test/RETI LOGICHE")
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(url.scheme == "claude")
        #expect(url.host() == "code")
        #expect(items.first { $0.name == "folder" }?.value == "/Users/test/RETI LOGICHE")
    }
}

@Suite struct SpotlightFiltering {
    @Test(arguments: [
        "/Users/test/Desktop/ELETTRONICA",
        "/Users/test/Downloads/appunti.pdf",
        "/Users/test/Library/CloudStorage/OneDrive-Polimi/corso",
    ])
    func `keeps real places`(path: String) {
        #expect(SpotlightSearch.isRelevant(path: path, home: home))
    }

    @Test(arguments: [
        "/Users/test/Library/Caches/automatica",
        "/Users/test/Library/Mobile Documents/com~apple~CloudDocs/automatica",
        "/Users/test/.Trash/automatica",
        "/Users/test/Desktop/x/node_modules/automatica",
        "/Users/test/Desktop/Foo.app/Contents/automatica",
        "/Users/other/Desktop/automatica",
        "/Users/testing/automatica",
    ])
    func `drops noise`(path: String) {
        #expect(!SpotlightSearch.isRelevant(path: path, home: home))
    }

    @Test func `the query escapes what would break it`() {
        #expect(SpotlightSearch.metadataQuery(for: #"a"b*c"#) == #"kMDItemFSName == "*a\"b\*c*"cd"#)
    }

    @Test func `the name shown drops the localized suffix`() {
        #expect(displayTitle(forPath: "/x/Media.localized") == "Media")
    }
}

@Suite struct Paths {
    @Test(arguments: [
        ("/Users/test/Desktop/2025-2026/AUTOMATICA", "~/Desktop/2025-2026"),
        ("/Users/test/Library/CloudStorage/OneDrive-Polimi/corso", "OneDrive-Polimi"),
    ])
    func `locations read like places`(path: String, expected: String) {
        #expect(PathDisplay.parent(of: path, home: home) == expected)
    }
}

@Suite struct Scanning {
    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "isearch-\(UUID().uuidString)")
        for path in [
            "2025-2026/ELETTRONICA/lab1/deep/too-deep",
            "repo/.git",
            "repo/inner",
            "x/node_modules/pkg",
            ".hidden/secret",
            "Foo.app/Contents",
        ] {
            try FileManager.default.createDirectory(at: root.appending(path: path), withIntermediateDirectories: true)
        }
    }

    private func scannedTitles(depth: Int = 3) -> Set<String> {
        Set(ProjectScanner.scan(roots: [ScanRoot(url: root, depth: depth)]).map(\.title))
    }

    @Test func `finds nested folders up to the depth`() {
        let titles = scannedTitles()
        #expect(titles.contains("ELETTRONICA"))
        #expect(titles.contains("lab1"))
        #expect(!titles.contains("deep"))
    }

    @Test func `stops at a project's root`() {
        let titles = scannedTitles()
        #expect(titles.contains("repo"))
        #expect(!titles.contains("inner"))
    }

    @Test func `skips noise, hidden folders and bundles`() {
        let titles = scannedTitles()
        #expect(!titles.contains("node_modules"))
        #expect(!titles.contains(".hidden"))
        #expect(!titles.contains("Foo.app"))
    }

    @Test func `excluded names hide everything below them`() {
        let items = ProjectScanner.scan(roots: [ScanRoot(url: root, depth: 3, excludedNames: ["2025-2026"])])
        #expect(!items.map(\.title).contains("ELETTRONICA"))
    }
}
