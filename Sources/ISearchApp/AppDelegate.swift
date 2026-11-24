import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let model = LauncherModel()
    private lazy var panelController = LauncherPanelController(model: model)
    private let hotKey = HotKey()
    private var statusItem: NSStatusItem?
    private var hotKeyMenuItem: NSMenuItem?
    private var loginMenuItem: NSMenuItem?

    private static let loginSetupDoneKey = "loginItemSetupDone"

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !isAnotherCopyRunning() else {
            NSApp.terminate(nil)
            return
        }
        installStatusItem()
        enableLoginItemOnFirstRun()
        model.refreshIndex()

        hotKey.onPress = { [panelController] in panelController.toggle() }
        let registered = hotKey.register()
        hotKeyMenuItem?.isHidden = registered

        // Used during development to open the bar on a given search without pressing the shortcut.
        let arguments = CommandLine.arguments
        if let flag = arguments.firstIndex(of: "--show"), arguments.indices.contains(flag + 1) {
            panelController.show(query: arguments[flag + 1])
        }
    }

    private func isAnotherCopyRunning() -> Bool {
        guard let identifier = Bundle.main.bundleIdentifier else { return false }
        let current = NSRunningApplication.current.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .contains { $0.processIdentifier != current }
    }

    // MARK: Menu bar

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "iSearch")

        let menu = NSMenu()
        menu.delegate = self
        let warning = NSMenuItem(title: "⌘Space unavailable: another app is using it", action: nil, keyEquivalent: "")
        warning.isEnabled = false
        warning.isHidden = true
        menu.addItem(warning)
        hotKeyMenuItem = warning

        menu.addItem(actionItem("Open iSearch", #selector(openBar)))
        menu.addItem(actionItem("Refresh Index", #selector(reindex)))
        menu.addItem(.separator())
        let login = actionItem("Open at Login", #selector(toggleLoginItem))
        menu.addItem(login)
        loginMenuItem = login
        menu.addItem(.separator())
        menu.addItem(actionItem("Quit iSearch", #selector(quit)))

        item.menu = menu
        statusItem = item
    }

    private func actionItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        loginMenuItem?.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func openBar() {
        panelController.show()
    }

    @objc private func reindex() {
        model.refreshIndex()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: Login item

    /// A launcher only helps if it is already running when the shortcut is pressed, so this is on from the first run.
    /// It only happens once: after that, the menu item decides. A copy run from the build folder never registers itself.
    private func enableLoginItemOnFirstRun() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.loginSetupDoneKey), Bundle.main.bundlePath.hasPrefix("/Applications/") else { return }
        defaults.set(true, forKey: Self.loginSetupDoneKey)
        try? SMAppService.mainApp.register()
    }

    @objc private func toggleLoginItem() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change Open at Login"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}
