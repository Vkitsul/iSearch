import Carbon.HIToolbox

/// The global ⌘Space shortcut. Carbon is still the only system API for a global shortcut that needs no Accessibility permission.
final class HotKey {
    var onPress: (() -> Void)?

    private var reference: EventHotKeyRef?
    private nonisolated(unsafe) static var current: HotKey?

    func register() -> Bool {
        Self.current = self

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ in
                // Carbon delivers application-target events on the main thread.
                MainActor.assumeIsolated { HotKey.current?.onPress?() }
                return noErr
            },
            1,
            &eventType,
            nil,
            nil
        )
        guard handlerStatus == noErr else { return false }

        let identifier = EventHotKeyID(signature: OSType(0x6953_7263), id: 1) // "iSrc"
        let status = RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(cmdKey),
            identifier,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        return status == noErr
    }
}
