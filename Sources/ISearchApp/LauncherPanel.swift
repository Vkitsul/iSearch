import AppKit
import SwiftUI

/// Takes keyboard input without activating the app, so whatever you were using stays frontmost and gets focus back on close.
final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class LauncherPanelController: NSObject, NSWindowDelegate {
    private let model: LauncherModel
    private let panel: LauncherPanel
    /// The top edge stays put while the height follows the results, so the search field never moves under your eyes.
    private var topEdge: CGFloat = 0

    private enum KeyCode {
        static let returnKey: UInt16 = 36
        static let keypadEnter: UInt16 = 76
        static let escape: UInt16 = 53
        static let down: UInt16 = 125
        static let up: UInt16 = 126
        static let n: UInt16 = 45
        static let p: UInt16 = 35
    }

    init(model: LauncherModel) {
        self.model = model
        panel = LauncherPanel(
            contentRect: NSRect(x: 0, y: 0, width: LauncherLayout.width, height: LauncherLayout.barHeight),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.level = .modalPanel
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        // Appears over the current Space, including a fullscreen app, instead of pulling you to another one.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.delegate = self

        let host = NSHostingView(rootView: LauncherView(model: model))
        host.sizingOptions = []
        panel.contentView = host

        model.onDismiss = { [weak self] in self?.hide() }
        model.onHeightChange = { [weak self] height in self?.resize(to: height) }
        installKeyMonitor()
    }

    func toggle() {
        if panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    func show(query: String = "") {
        let screen = screenUnderMouse()
        let visible = screen.visibleFrame
        topEdge = visible.minY + visible.height * 0.74
        model.prepareForPresentation(query: query)
        place(height: model.panelHeight, on: screen)
        panel.makeKeyAndOrderFront(nil)
    }

    private func hide() {
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    private func screenUnderMouse() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func place(height: CGFloat, on screen: NSScreen) {
        let originX = screen.visibleFrame.midX - LauncherLayout.width / 2
        panel.setFrame(NSRect(x: originX, y: topEdge - height, width: LauncherLayout.width, height: height), display: true)
        panel.invalidateShadow()
    }

    private func resize(to height: CGFloat) {
        guard panel.isVisible, panel.frame.height != height else { return }
        let frame = panel.frame
        panel.setFrame(NSRect(x: frame.minX, y: topEdge - height, width: frame.width, height: height), display: true)
        panel.invalidateShadow()
    }

    // MARK: Keyboard

    /// Handled here rather than in SwiftUI because the text field would otherwise consume the arrows and Return first.
    private func installKeyMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow, self.handle(event) else { return event }
            return nil
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        // An accent still being composed needs Return and Escape for itself.
        if let editor = panel.firstResponder as? NSTextView, editor.hasMarkedText() { return false }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch event.keyCode {
        case KeyCode.down:
            model.moveSelection(by: 1)
        case KeyCode.up:
            model.moveSelection(by: -1)
        case KeyCode.n where modifiers.contains(.control):
            model.moveSelection(by: 1)
        case KeyCode.p where modifiers.contains(.control):
            model.moveSelection(by: -1)
        case KeyCode.escape:
            hide()
        case KeyCode.returnKey, KeyCode.keypadEnter:
            if modifiers.contains(.command) {
                model.askClaude(incognito: false)
            } else if modifiers.contains(.option) {
                model.askClaude(incognito: true)
            } else if modifiers.contains(.shift) {
                model.runSecondaryAction()
            } else {
                model.runSelection()
            }
        default:
            return false
        }
        return true
    }
}
