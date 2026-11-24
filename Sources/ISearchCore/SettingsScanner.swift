import Foundation

/// Reads the pages of System Settings from macOS itself, so the list follows each macOS update.
public enum SettingsScanner {
    public static let defaultRoot = URL(filePath: "/System/Library/ExtensionKit/Extensions")

    private static let settingsApp = "/System/Applications/System Settings.app"
    private static let settingsExtensionPoint = "com.apple.Settings.extension.ui"
    private static let urlScheme = "x-apple.systempreferences:"

    /// These pages exist on disk but are not something a person navigates to.
    private static let hiddenPanes: Set<String> = [
        "com.apple.FollowUpSettings.FollowUpSettingsExtension",
        "com.apple.ClassKit-Settings.extension",
        "com.apple.Classroom-Settings.extension",
    ]

    /// The few pages whose names macOS does not store in a usable form.
    private static let missingNames: [String: String] = [
        "com.apple.Battery-Settings.extension": "Battery",
        "com.apple.Wallpaper-Settings.extension": "Wallpaper",
    ]

    /// Everyday words for a page that macOS's own search terms leave out.
    private static let extraKeywords: [String: [String]] = [
        "com.apple.Displays-Settings.extension": ["display", "monitor", "screen"],
        "com.apple.Battery-Settings.extension": ["energy"],
        "com.apple.wifi-settings-extension": ["wifi", "wi-fi", "wi fi"],
        "com.apple.Sound-Settings.extension": ["audio", "volume"],
        "com.apple.Keyboard-Settings.extension": ["shortcut", "shortcuts"],
        "com.apple.Desktop-Settings.extension": ["dock"],
        "com.apple.Appearance-Settings.extension": ["theme"],
        "com.apple.Focus-Settings.extension": ["do not disturb"],
        "com.apple.Software-Update-Settings.extension": ["update", "updates"],
        "com.apple.systempreferences.AppleIDSettings": ["icloud"],
        "com.apple.settings.Storage": ["disk"],
    ]

    public static func scan(root: URL = defaultRoot) -> [SearchItem] {
        guard let bundles = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
            return []
        }
        return bundles
            .filter { $0.pathExtension == "appex" }
            .flatMap(items(forExtension:))
    }

    private static func items(forExtension bundle: URL) -> [SearchItem] {
        let contents = bundle.appending(path: "Contents")
        guard let info = readPlist(contents.appending(path: "Info.plist")),
              let identifier = info["CFBundleIdentifier"] as? String,
              !hiddenPanes.contains(identifier),
              let attributes = info["EXAppExtensionAttributes"] as? [String: Any],
              attributes["EXExtensionPointIdentifier"] as? String == settingsExtensionPoint,
              let settings = attributes["SettingsExtensionAttributes"] as? [String: Any],
              settings["allowsXAppleSystemPreferencesURLScheme"] as? Bool == true,
              let title = paneName(identifier: identifier, contents: contents, info: info)
        else { return [] }

        let pane = SearchItem(
            path: "settings://\(identifier)",
            kind: .settingsPane,
            title: title,
            keywords: extraKeywords[identifier] ?? [],
            openURL: settingsURL(identifier: identifier),
            iconPath: settingsApp,
            context: "System Settings"
        )
        let entries = entryItems(identifier: identifier, paneTitle: title, resources: contents.appending(path: "Resources"))
        return [pane] + entries
    }

    private static func paneName(identifier: String, contents: URL, info: [String: Any]) -> String? {
        if let name = missingNames[identifier] { return name }
        let table = readPlist(contents.appending(path: "Resources/InfoPlist.loctable"))
        let strings = table?["en"] as? [String: Any]
        // macOS often leaves a page's English name out of the table and keeps it in Info.plist instead.
        let candidates = [strings?["CFBundleDisplayName"], strings?["CFBundleName"], info["CFBundleDisplayName"]]
        return candidates.lazy.compactMap { $0 as? String }.first { !looksInternal($0) }
    }

    /// Some bundles only hold a code name such as "HeadphoneSettingsExtension" or "PowerPreferences".
    static func looksInternal(_ name: String) -> Bool {
        guard !name.contains(" ") else { return false }
        return ["Extension", "Settings", "Preferences", "Ext"].contains { name.hasSuffix($0) }
    }

    // MARK: Entries inside a page

    /// Each `.searchTerms` file maps an anchor (the spot to jump to inside the page) to the entries found there.
    private static func entryItems(identifier: String, paneTitle: String, resources: URL) -> [SearchItem] {
        let folder = resources.appending(path: "en.lproj")
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
            return []
        }

        var items: [SearchItem] = []
        for table in files.filter({ $0.pathExtension == "searchTerms" }).compactMap(readPlist) {
            for (anchor, value) in table {
                let strings = (value as? [String: Any])?["localizableStrings"] as? [[String: Any]] ?? []
                for (position, string) in strings.enumerated() {
                    guard let title = string["title"] as? String, !title.isEmpty else { continue }
                    items.append(SearchItem(
                        path: "settings://\(identifier)/\(anchor)/\(position)",
                        kind: .setting,
                        title: title,
                        keywords: keywords(fromIndex: string["index"] as? String ?? ""),
                        openURL: settingsURL(identifier: identifier, anchor: anchor),
                        iconPath: settingsApp,
                        context: "Settings › \(paneTitle)"
                    ))
                }
            }
        }
        return items
    }

    /// Keeps each phrase and its single words, so "ambient light" is found by "ambient light" and by "ambient".
    static func keywords(fromIndex index: String) -> [String] {
        var result: [String] = []
        for phrase in index.split(separator: ",") {
            let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            result.append(trimmed)
            let words = trimmed.split(whereSeparator: \.isWhitespace)
            if words.count > 1 { result += words.map(String.init) }
        }
        return result
    }

    static func settingsURL(identifier: String, anchor: String? = nil) -> URL {
        let text = anchor.map { "\(urlScheme)\(identifier)?\($0)" } ?? "\(urlScheme)\(identifier)"
        // Falls back to the page when an anchor cannot be part of a URL. Identifiers come from macOS and are plain ASCII.
        return URL(string: text) ?? URL(string: "\(urlScheme)\(identifier)") ?? URL(filePath: settingsApp)
    }
}

private func readPlist(_ url: URL) -> [String: Any]? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
}
