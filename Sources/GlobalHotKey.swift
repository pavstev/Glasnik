import Carbon.HIToolbox

/// The global shortcut: ⌥⇧Space. Picked to dodge this machine's launcher/WM —
/// Raycast owns ⌘Space and AeroSpace binds ⌥+letters/digits (but never ⌥⇧Space).
enum GlasnikShortcut {
    /// Carbon virtual key code for the space bar.
    static let keyCode = UInt32(kVK_Space)
    /// Carbon modifier mask: Option + Shift.
    static let modifiers = UInt32(optionKey | shiftKey)
    /// Human-readable form for the UI.
    static let display = "⌥⇧Space"
}

/// Registers a system-wide hotkey via Carbon's `RegisterEventHotKey` — the same
/// mechanism KeyboardShortcuts uses internally. It needs no special permission and,
/// unlike a SwiftUI-macro-based dependency, builds cleanly with the Command Line
/// Tools (no Xcode required).
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let onPressed: () -> Void

    /// Returns `nil` if the OS refused to install the handler or register the key.
    init?(keyCode: UInt32, modifiers: UInt32, onPressed: @escaping () -> Void) {
        self.onPressed = onPressed

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // Pass an unretained pointer to self into the C callback via userData.
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                hotKey.onPressed()
                return noErr
            },
            1,
            &eventSpec,
            selfPointer,
            &eventHandler
        )
        guard installStatus == noErr else { return nil }

        let hotKeyID = EventHotKeyID(signature: OSType(0x474C_4E4B), id: 1) // 'GLNK'
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        guard registerStatus == noErr else {
            if let eventHandler { RemoveEventHandler(eventHandler) }
            return nil
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}
