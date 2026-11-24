import Foundation

/// Live search of the whole home folder through Spotlight, covering what the project scan leaves out: files, Downloads, OneDrive.
public enum SpotlightSearch {
    /// `mdfind` can match a huge number of files for a short query. Everything useful fits well below this.
    private static let maxOutputBytes = 2_000_000
    private static let maxResults = 300

    /// Matches names with a word starting with the text. A leading `*` (any substring) took 0.28 s per query instead of 0.07 s on this Mac,
    /// and only adds mid-word hits like "tronica" in "elettronica", which the local index still finds for projects.
    public static func metadataQuery(for text: String) -> String {
        var escaped = ""
        for character in text {
            if "\\\"*?".contains(character) { escaped.append("\\") }
            escaped.append(character)
        }
        return "kMDItemFSName == \"\(escaped)*\"cdw"
    }

    /// Hides hidden folders, build output, the insides of bundles and `Library`, including iCloud Drive. Only cloud drives such as OneDrive stay.
    public static func isRelevant(path: String, home: String) -> Bool {
        guard path.hasPrefix(home + "/") else { return false }
        let relative = path.dropFirst(home.count + 1)
        let components = relative.split(separator: "/").map(String.init)

        if components.first == "Library" {
            guard components.count > 1, components[1] == "CloudStorage" else { return false }
        }
        for (position, component) in components.enumerated() {
            if component.hasPrefix(".") || NoiseFolders.names.contains(component) { return false }
            let isContainer = position < components.count - 1
            if isContainer, NoiseFolders.bundleExtensions.contains((component as NSString).pathExtension) { return false }
        }
        return true
    }

    public static func items(fromOutput output: Data, home: String) -> [SearchItem] {
        var results: [SearchItem] = []
        for pathBytes in output.split(separator: 0) {
            guard results.count < maxResults, let path = String(data: Data(pathBytes), encoding: .utf8) else { continue }
            guard isRelevant(path: path, home: home), let item = item(atPath: path) else { continue }
            results.append(item)
        }
        return results
    }

    private static func item(atPath path: String) -> SearchItem? {
        let url = URL(filePath: path)
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey]) else {
            return nil
        }
        let kind: SearchItem.Kind
        if url.pathExtension == "app" {
            kind = .app
        } else {
            kind = values.isDirectory == true ? .folder : .file
        }
        return SearchItem(path: path, kind: kind, title: displayTitle(forPath: path), modified: values.contentModificationDate)
    }

    /// Cancelling the calling task stops `mdfind`.
    @concurrent
    public static func search(text: String, home: String) async -> [SearchItem] {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/mdfind")
        process.arguments = ["-0", "-onlyin", home, metadataQuery(for: text)]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }

        let running = RunningProcess(process)
        let output = await withTaskCancellationHandler {
            await readOutput(of: running, from: pipe.fileHandleForReading)
        } onCancel: {
            running.stop()
        }
        guard !Task.isCancelled else { return [] }
        return items(fromOutput: output, home: home)
    }

    @concurrent
    private static func readOutput(of process: RunningProcess, from handle: FileHandle) async -> Data {
        var output = Data()
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { return output }
            output.append(chunk)
            if output.count > maxOutputBytes {
                process.stop()
                return output
            }
        }
    }
}

/// `Process` is not `Sendable`, but `terminate()` is documented as safe to call from any thread and nothing else is touched after launch.
private final class RunningProcess: @unchecked Sendable {
    private let process: Process

    init(_ process: Process) {
        self.process = process
    }

    func stop() {
        if process.isRunning { process.terminate() }
    }
}
