import SwiftUI

/// App entry point.
///
/// Šapat is a menu bar agent (`LSUIElement`), so there is no main window and no
/// Dock icon. All UI lives in an `NSPopover` anchored to an `NSStatusItem`, both
/// owned by `AppDelegate`. We deliberately use AppKit for the status item + popover
/// (instead of SwiftUI `MenuBarExtra`) because macOS 14 has no reliable public API
/// to open a `MenuBarExtra` window programmatically — and the global hotkey must be
/// able to pop the window open from any app.
///
/// The only SwiftUI `Scene` is `Settings`, which provides the standard preferences
/// window (reachable via the hotkey recorder embedded in the popover footer too).
@main
struct SapatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}
