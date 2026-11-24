// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "iSearch",
    platforms: [.macOS(.v14)],
    targets: [
        // Search logic with no UI, so it can be tested without launching the app.
        .target(name: "ISearchCore"),
        .executableTarget(
            name: "ISearchApp",
            dependencies: ["ISearchCore"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "ISearchCoreTests", dependencies: ["ISearchCore"]),
    ]
)
