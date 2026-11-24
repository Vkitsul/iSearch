import Foundation

/// Folders that are never someone's project and would only bury the real results.
enum NoiseFolders {
    static let names: Set<String> = [
        "node_modules", "__pycache__", "venv", "env", "DerivedData", "Pods", "target", "dist", "build",
        "$RECYCLE.BIN", "System Volume Information", "site-packages",
    ]
    static let bundleExtensions: Set<String> = [
        "app", "framework", "bundle", "photoslibrary", "musiclibrary", "xcodeproj", "xcworkspace", "plugin", "kext",
    ]
}

/// A folder to walk, and how deep. Walking is limited to where work lives: a full home scan took more than a minute on this Mac.
public struct ScanRoot: Sendable {
    public let url: URL
    public let depth: Int
    public let excludedNames: Set<String>

    public init(url: URL, depth: Int, excludedNames: Set<String> = []) {
        self.url = url
        self.depth = depth
        self.excludedNames = excludedNames
    }
}

public enum ProjectScanner {
    /// A folder containing one of these is a project, so its subfolders are not listed on their own.
    private static let projectMarkers: Set<String> = [
        ".git", "Package.swift", "package.json", "pyproject.toml", "requirements.txt", "Cargo.toml",
        "CMakeLists.txt", "pom.xml", "build.gradle", "go.mod", "Makefile", ".idea",
    ]

    public static func defaultRoots(home: URL) -> [ScanRoot] {
        [
            ScanRoot(url: home.appending(path: "Desktop"), depth: 3),
            ScanRoot(url: home.appending(path: "Documents"), depth: 3),
            // Top of the home folder, for places like PycharmProjects. Downloads and the media folders are left to Spotlight.
            ScanRoot(
                url: home,
                depth: 2,
                excludedNames: ["Library", "Desktop", "Documents", "Downloads", "Music", "Movies", "Pictures", "Public", "Applications"]
            ),
        ]
    }

    public static func scan(roots: [ScanRoot], limit: Int = 20_000) -> [SearchItem] {
        var found: [String: SearchItem] = [:]
        for root in roots {
            walk(root.url, remainingDepth: root.depth, excluded: root.excludedNames, limit: limit, into: &found)
        }
        return Array(found.values)
    }

    private static func walk(
        _ directory: URL,
        remainingDepth: Int,
        excluded: Set<String>,
        limit: Int,
        into found: inout [String: SearchItem]
    ) {
        guard remainingDepth > 0, found.count < limit else { return }
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey, .contentModificationDateKey]
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return }

        for child in children {
            let name = child.lastPathComponent
            guard !excluded.contains(name), !NoiseFolders.names.contains(name) else { continue }
            guard let values = try? child.resourceValues(forKeys: keys),
                  values.isDirectory == true, values.isPackage != true else { continue }

            found[child.path] = SearchItem(
                path: child.path,
                kind: .project,
                title: displayTitle(forPath: child.path),
                modified: values.contentModificationDate
            )
            if !isProject(child) {
                walk(child, remainingDepth: remainingDepth - 1, excluded: [], limit: limit, into: &found)
            }
        }
    }

    private static func isProject(_ directory: URL) -> Bool {
        projectMarkers.contains { FileManager.default.fileExists(atPath: directory.appending(path: $0).path) }
    }
}

public enum AppScanner {
    public static func scan(home: URL) -> [SearchItem] {
        let folders = [
            "/Applications", "/System/Applications", "/System/Applications/Utilities",
            "/System/Library/CoreServices/Applications", home.appending(path: "Applications").path,
        ]
        var found: [String: SearchItem] = [:]
        for folder in folders {
            collect(in: URL(filePath: folder), nestedLevels: 1, into: &found)
        }
        let finder = "/System/Library/CoreServices/Finder.app"
        found[finder] = item(forApp: finder)
        return Array(found.values)
    }

    private static func collect(in folder: URL, nestedLevels: Int, into found: inout [String: SearchItem]) {
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for child in children {
            // Checked by extension first: Safari is a symlink on recent macOS, so it does not report as a directory.
            if child.pathExtension == "app" {
                found[child.path] = item(forApp: child.path)
            } else if nestedLevels > 0, (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                collect(in: child, nestedLevels: nestedLevels - 1, into: &found)
            }
        }
    }

    private static func item(forApp path: String) -> SearchItem {
        let fileName = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        var localized = FileManager.default.displayName(atPath: path)
        if localized.hasSuffix(".app") { localized = String(localized.dropLast(4)) }
        return SearchItem(path: path, kind: .app, title: localized, alternativeNames: [fileName])
    }
}

public enum LocalIndex {
    /// Runs off the main thread: the first scan can also sit waiting for the Desktop and Documents permission prompts.
    @concurrent
    public static func build(home: URL) async -> [SearchItem] {
        async let apps = AppScanner.scan(home: home)
        async let projects = ProjectScanner.scan(roots: ProjectScanner.defaultRoots(home: home))
        async let settings = SettingsScanner.scan()
        return await apps + projects + settings
    }
}

func displayTitle(forPath path: String) -> String {
    let name = (path as NSString).lastPathComponent
    return name.hasSuffix(".localized") ? String(name.dropLast(".localized".count)) : name
}
