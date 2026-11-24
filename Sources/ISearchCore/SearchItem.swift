import Foundation

/// Something on this Mac that the bar can open.
public struct SearchItem: Sendable, Hashable, Identifiable {
    public enum Kind: Sendable, Hashable {
        case app
        /// A folder found by the project scan: the places where the user actually keeps their work.
        case project
        /// A folder that only Spotlight found.
        case folder
        case file
        /// A whole page of System Settings, such as Displays.
        case settingsPane
        /// One entry inside a page, such as True Tone.
        case setting
    }

    /// Unique identity. For settings this is not a real file path, so use `openURL` and `iconPath` rather than reading it.
    public let path: String
    public let kind: Kind
    public let title: String
    public let modified: Date?
    /// Normalized names to match against: the display name plus any alternative, such as an app's file name.
    public let searchKeys: [String]
    /// Normalized terms that only count when typed in full. They describe the item rather than name it, so partial matches would be noise.
    public let keywords: Set<String>
    public let openURL: URL
    public let iconPath: String
    private let context: String?

    public var id: String { path }

    public init(
        path: String,
        kind: Kind,
        title: String,
        alternativeNames: [String] = [],
        keywords: [String] = [],
        modified: Date? = nil,
        openURL: URL? = nil,
        iconPath: String? = nil,
        context: String? = nil
    ) {
        self.path = path
        self.kind = kind
        self.title = title
        self.modified = modified
        self.openURL = openURL ?? URL(filePath: path)
        self.iconPath = iconPath ?? path
        self.context = context
        var keys = [FuzzyMatcher.normalize(title)]
        for name in alternativeNames {
            let key = FuzzyMatcher.normalize(name)
            if !keys.contains(key) { keys.append(key) }
        }
        searchKeys = keys
        self.keywords = Set(keywords.map(FuzzyMatcher.normalize))
    }

    /// Where the item lives, in readable form: this tells apart two folders with the same name.
    public func location(home: String) -> String {
        context ?? PathDisplay.parent(of: path, home: home)
    }
}

public enum PathDisplay {
    private static let cloudStorageRoot = "/Library/CloudStorage/"

    public static func parent(of path: String, home: String) -> String {
        readable((path as NSString).deletingLastPathComponent, home: home)
    }

    public static func readable(_ path: String, home: String) -> String {
        guard path.hasPrefix(home) else { return path }
        let relative = String(path.dropFirst(home.count))
        if relative.hasPrefix(cloudStorageRoot) {
            return String(relative.dropFirst(cloudStorageRoot.count))
        }
        return "~" + relative
    }
}
