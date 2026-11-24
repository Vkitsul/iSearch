import AppKit
import ISearchCore
import Observation

enum LauncherLayout {
    static let width: CGFloat = 680
    static let barHeight: CGFloat = 56
    static let rowHeight: CGFloat = 44
    static let sectionHeaderHeight: CGFloat = 26
    static let footerHeight: CGFloat = 32
    static let listPadding: CGFloat = 12
    static let maxListHeight: CGFloat = 420
}

@Observable
final class LauncherModel {
    var query = "" {
        didSet {
            guard query != oldValue else { return }
            queryDidChange()
        }
    }

    private(set) var sections: [ResultSection] = []
    private(set) var selection = 0
    /// Changes each time the bar opens, which is the view's cue to take keyboard focus.
    private(set) var presentationCount = 0

    /// Asks the panel to close. Set by the panel controller.
    @ObservationIgnored var onDismiss: () -> Void = {}
    /// Reports the height the panel should now have. Set by the panel controller.
    @ObservationIgnored var onHeightChange: (CGFloat) -> Void = { _ in }

    let home = FileManager.default.homeDirectoryForCurrentUser.path

    @ObservationIgnored private var index: [SearchItem] = []
    @ObservationIgnored private var spotlightItems: [SearchItem] = []
    @ObservationIgnored private var spotlightTask: Task<Void, Never>?
    @ObservationIgnored private var lastIndexed: Date?
    @ObservationIgnored private var selectionMovedByUser = false
    @ObservationIgnored private let usageStore = UsageStore()

    private static let indexMaxAge: TimeInterval = 300
    private static let spotlightDelay: Duration = .milliseconds(120)
    private static let recentLimit = 6

    var rows: [ResultRow] {
        sections.flatMap(\.rows)
    }

    var selectedRow: ResultRow? {
        let all = rows
        return all.indices.contains(selection) ? all[selection] : nil
    }

    var listHeight: CGFloat {
        guard !sections.isEmpty else { return 0 }
        let content = sections.reduce(LauncherLayout.listPadding) { total, section in
            total + LauncherLayout.sectionHeaderHeight + CGFloat(section.rows.count) * LauncherLayout.rowHeight
        }
        return min(content, LauncherLayout.maxListHeight)
    }

    var panelHeight: CGFloat {
        sections.isEmpty
            ? LauncherLayout.barHeight
            : LauncherLayout.barHeight + listHeight + LauncherLayout.footerHeight
    }

    // MARK: Opening and closing

    func prepareForPresentation(query initial: String) {
        presentationCount += 1
        query = initial
        recompute()
        // Catches new apps and folders without a background watcher. Spotlight already covers anything newer in the meantime.
        if let lastIndexed, Date.now.timeIntervalSince(lastIndexed) > Self.indexMaxAge {
            refreshIndex()
        }
    }

    func refreshIndex() {
        lastIndexed = .now
        let homeURL = URL(filePath: home)
        Task {
            index = await LocalIndex.build(home: homeURL)
            recompute()
        }
    }

    // MARK: Searching

    private func queryDidChange() {
        selectionMovedByUser = false
        spotlightTask?.cancel()
        recompute()

        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2 else {
            spotlightItems = []
            return
        }
        let home = home
        spotlightTask = Task {
            try? await Task.sleep(for: Self.spotlightDelay)
            guard !Task.isCancelled else { return }
            let found = await SpotlightSearch.search(text: text, home: home)
            guard !Task.isCancelled else { return }
            spotlightItems = found
            recompute()
        }
    }

    private func recompute() {
        let previous = selectedRow
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections = recentSections()
        } else {
            // The index goes first so that a path found by both keeps its higher-ranked kind.
            let ranked = Ranker.rank(query: query, items: index + spotlightItems, usage: usageStore.history, now: .now)
            sections = ResultComposer.compose(query: query, ranked: ranked)
        }

        // Late Spotlight results must not pull the selection away from a row the user moved to.
        let all = rows
        if selectionMovedByUser, let previous, let kept = all.firstIndex(of: previous) {
            selection = kept
        } else {
            selection = 0
            selectionMovedByUser = false
        }
        onHeightChange(panelHeight)
    }

    private func recentSections() -> [ResultSection] {
        let known = Dictionary(index.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        let items = usageStore.history
            .recentPaths(limit: Self.recentLimit, now: .now)
            .compactMap { known[$0] ?? recentItem(atPath: $0) }
        return items.isEmpty ? [] : [ResultSection(title: "Recent", rows: items.map { .item($0) })]
    }

    /// For a recent file or Spotlight folder, which is not in the index. Returns nil once the path no longer exists.
    private func recentItem(atPath path: String) -> SearchItem? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { return nil }
        let name = (path as NSString).lastPathComponent
        return SearchItem(path: path, kind: isDirectory.boolValue ? .folder : .file, title: name)
    }

    // MARK: Keyboard

    func moveSelection(by delta: Int) {
        let count = rows.count
        guard count > 0 else { return }
        selectionMovedByUser = true
        selection = (selection + delta + count) % count
    }

    func runSelection() {
        guard let row = selectedRow else { return }
        run(row)
    }

    func run(_ row: ResultRow) {
        switch row {
        case .item(let item):
            usageStore.record(path: item.path)
            finish { NSWorkspace.shared.open(item.openURL) }
        case .claude(let prompt, let incognito):
            askClaude(prompt: prompt, incognito: incognito)
        }
    }

    func askClaude(incognito: Bool) {
        askClaude(prompt: query, incognito: incognito)
    }

    private func askClaude(prompt: String, incognito: Bool) {
        let url: URL
        if incognito {
            url = ClaudeLink.incognitoChat(prompt: prompt)
        } else if NSWorkspace.shared.urlForApplication(toOpen: ClaudeLink.chat(prompt: "")) != nil {
            url = ClaudeLink.chat(prompt: prompt)
        } else {
            url = ClaudeLink.webChat(prompt: prompt)
        }
        finish { NSWorkspace.shared.open(url) }
    }

    /// ⇧↵: Claude Code in a folder, or the Finder for a file.
    func runSecondaryAction() {
        guard case .item(let item) = selectedRow else { return }
        switch item.kind {
        case .project, .folder:
            usageStore.record(path: item.path)
            finish { NSWorkspace.shared.open(ClaudeLink.codeSession(folder: item.path)) }
        case .file:
            usageStore.record(path: item.path)
            finish {
                NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: item.path)])
                return true
            }
        case .app, .settingsPane, .setting:
            break
        }
    }

    private func finish(_ open: () -> Bool) {
        onDismiss()
        if !open() { NSSound.beep() }
    }

    func dismiss() {
        onDismiss()
    }
}

/// Saved as a small JSON file, so usage ranking survives restarts.
final class UsageStore {
    private(set) var history = UsageHistory()
    private let fileURL: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        fileURL = support.appending(path: "iSearch/usage.json")
        if let data = try? Data(contentsOf: fileURL), let saved = try? JSONDecoder().decode(UsageHistory.self, from: data) {
            history = saved
        }
    }

    func record(path: String) {
        history.record(path: path, at: .now)
        guard let data = try? JSONEncoder().encode(history) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
