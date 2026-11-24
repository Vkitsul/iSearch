import Foundation
import Testing
@testable import ISearchCore

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func rank(_ query: String, _ items: [SearchItem]) -> [SearchItem] {
    Ranker.rank(query: query, items: items, usage: UsageHistory(), now: now).map(\.item)
}

/// A miniature copy of the bundle layout macOS uses, so these tests do not depend on one macOS version.
@Suite struct SettingsScanning {
    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "isearch-settings-\(UUID().uuidString)")
        try makePane(
            folder: "Displays",
            identifier: "com.apple.Displays-Settings.extension",
            names: ["en": "Displays", "it": "Schermi"],
            terms: [
                "en": ["ambience": [["title": "True Tone", "index": "ambient light, white balance"]]],
                "it": ["ambience": [["title": "Tono reale", "index": "luce ambientale, bilanciamento del bianco"]]],
            ]
        )
        try makePane(folder: "NoLink", identifier: "com.apple.NoLink", names: ["en": "No Link"], allowsLink: false)
        try makePane(folder: "Other", identifier: "com.apple.Other", names: ["en": "Other"], extensionPoint: "com.apple.widget")
        try makePane(folder: "Internal", identifier: "com.apple.Internal", names: ["en": "HeadphoneSettingsExtension"])
        try makePane(folder: "Follow", identifier: "com.apple.FollowUpSettings.FollowUpSettingsExtension", names: ["en": "FollowUps"])
    }

    private func makePane(
        folder: String,
        identifier: String,
        names: [String: String],
        terms: [String: [String: [[String: String]]]] = [:],
        allowsLink: Bool = true,
        extensionPoint: String = "com.apple.Settings.extension.ui"
    ) throws {
        let contents = root.appending(path: "\(folder).appex/Contents")
        let resources = contents.appending(path: "Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)

        try write([
            "CFBundleIdentifier": identifier,
            "EXAppExtensionAttributes": [
                "EXExtensionPointIdentifier": extensionPoint,
                "SettingsExtensionAttributes": ["allowsXAppleSystemPreferencesURLScheme": allowsLink],
            ],
        ], to: contents.appending(path: "Info.plist"))

        let table = names.mapValues { ["CFBundleDisplayName": $0] }
        try write(table, to: resources.appending(path: "InfoPlist.loctable"))

        for (language, anchors) in terms {
            let folder = resources.appending(path: "\(language).lproj")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let content = anchors.mapValues { ["localizableStrings": $0] }
            try write(content, to: folder.appending(path: "Terms.searchTerms"))
        }
    }

    private func write(_ plist: Any, to url: URL) throws {
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: url)
    }

    private var scanned: [SearchItem] {
        SettingsScanner.scan(root: root)
    }

    @Test func `finds a page and the entries inside it`() {
        #expect(Set(scanned.map(\.title)) == ["Displays", "True Tone"])
    }

    @Test func `skips code names and what cannot be linked to`() {
        let titles = scanned.map(\.title)
        for hidden in ["No Link", "Other", "HeadphoneSettingsExtension", "FollowUps"] {
            #expect(!titles.contains(hidden))
        }
    }

    @Test(arguments: ["schermi", "tono reale", "bilanciamento del bianco", "ambientale"])
    func `Italian text is not loaded`(query: String) {
        #expect(rank(query, scanned).isEmpty)
    }

    @Test(arguments: ["display", "displays", "monitor", "screen"])
    func `a page is found by its name or a common word`(query: String) {
        #expect(rank(query, scanned).first?.title == "Displays")
    }

    @Test(arguments: ["true tone", "white balance", "ambient"])
    func `an entry is found by name or by what it does`(query: String) {
        #expect(rank(query, scanned).first?.title == "True Tone")
    }

    @Test func `links open the page, or the exact spot inside it`() throws {
        let pane = try #require(scanned.first { $0.title == "Displays" })
        let entry = try #require(scanned.first { $0.title == "True Tone" })
        #expect(pane.openURL.absoluteString == "x-apple.systempreferences:com.apple.Displays-Settings.extension")
        #expect(entry.openURL.absoluteString == "x-apple.systempreferences:com.apple.Displays-Settings.extension?ambience")
    }

    @Test func `rows say where they are, with the Settings icon`() throws {
        let pane = try #require(scanned.first { $0.title == "Displays" })
        let entry = try #require(scanned.first { $0.title == "True Tone" })
        #expect(pane.location(home: "/Users/test") == "System Settings")
        #expect(entry.location(home: "/Users/test") == "Settings › Displays")
        #expect(entry.iconPath == "/System/Applications/System Settings.app")
    }
}

@Suite struct SettingsRanking {
    private func setting(_ title: String, keywords: [String] = [], kind: SearchItem.Kind = .setting) -> SearchItem {
        SearchItem(path: "settings://\(title)", kind: kind, title: title, keywords: keywords)
    }

    @Test func `the page comes before an entry with the same name`() {
        let ranked = rank("sound", [setting("Sound"), setting("Sound", kind: .settingsPane).withPath("settings://pane")])
        #expect(ranked.first?.kind == .settingsPane)
    }

    @Test func `a keyword must be typed in full`() {
        let item = setting("Refresh Rate", keywords: ["hertz"])
        #expect(rank("hertz", [item]).count == 1)
        #expect(rank("hert", [item]).isEmpty)
    }

    @Test func `very short keywords are ignored`() {
        #expect(rank("di", [setting("Refresh Rate", keywords: ["di"])]).isEmpty)
    }

    @Test func `a scattered match on a setting's name is noise`() {
        #expect(rank("rfrt", [setting("Refresh Rate")]).isEmpty)
    }

    @Test func `a project with the same word still wins over a setting`() {
        let project = SearchItem(path: "/x/AUTOMATICA", kind: .project, title: "AUTOMATICA")
        let ranked = rank("automatica", [setting("Regola automaticamente"), project])
        #expect(ranked.first?.kind == .project)
    }

    @Test func `settings get their own section`() {
        let scored = Ranker.rank(query: "tone", items: [setting("True Tone")], usage: UsageHistory(), now: now)
        let sections = ResultComposer.compose(query: "tone", ranked: scored)
        #expect(sections.map(\.title) == ["Settings", "Claude"])
    }

    @Test(arguments: ["phrase, other", " phrase ,other "])
    func `keywords split into phrases and words`(index: String) {
        #expect(SettingsScanner.keywords(fromIndex: index) == ["phrase", "other"])
    }

    @Test func `a phrase also counts word by word`() {
        #expect(SettingsScanner.keywords(fromIndex: "ambient light") == ["ambient light", "ambient", "light"])
    }
}

extension SearchItem {
    fileprivate func withPath(_ newPath: String) -> SearchItem {
        SearchItem(path: newPath, kind: kind, title: title)
    }
}

/// Reads the real System Settings on this Mac, in case a macOS update changes the layout these files rely on.
@Suite(.enabled(if: FileManager.default.fileExists(atPath: SettingsScanner.defaultRoot.path)))
struct LiveSystemSettings {
    private let items = SettingsScanner.scan()

    @Test(arguments: [
        ("display", "Displays"),
        ("wifi", "Wi\u{2011}Fi"),
        ("battery", "Battery"),
        ("keyboard", "Keyboard"),
        ("bluetooth", "Bluetooth"),
        ("privacy", "Privacy & Security"),
        ("vpn", "VPN"),
        ("storage", "Storage"),
        ("wallpaper", "Wallpaper"),
        ("touch id", "Touch ID & Password"),
        ("apple account", "Apple Account"),
    ])
    func `common pages are found`(query: String, expected: String) {
        #expect(rank(query, items).first?.title == expected)
    }

    @Test func `there are real entries, not just pages`() {
        #expect(items.count(where: { $0.kind == .settingsPane }) > 30)
        #expect(items.count(where: { $0.kind == .setting }) > 100)
    }

    @Test func `System Settings itself is found`() {
        let apps = AppScanner.scan(home: FileManager.default.temporaryDirectory)
        #expect(rank("settings", apps).first?.path == "/System/Applications/System Settings.app")
    }
}
