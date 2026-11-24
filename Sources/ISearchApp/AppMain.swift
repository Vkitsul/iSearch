import AppKit

@main
enum AppMain {
    // Held here because NSApplication only keeps a weak reference to its delegate.
    private static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.run()
    }
}
