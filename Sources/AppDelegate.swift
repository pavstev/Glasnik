import AppKit
import SwiftUI

/// Owns the menu bar status item, the popover, the global hotkey, and the shared
/// observable objects. Using AppKit here (rather than SwiftUI `MenuBarExtra`) gives
/// us full, reliable control over showing the popover — required so the global
/// hotkey can pop it open from any app on macOS 14.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let viewModel = RecorderViewModel()
    let updateChecker = UpdateChecker()

    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var hotKey: GlobalHotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configurePopover()
        configureStatusItem()
        registerHotkey()

        viewModel.onStateChange = { [weak self] state in
            self?.updateStatusIcon(for: state)
        }
        viewModel.onRequestClose = { [weak self] in
            self?.popover.performClose(nil)
        }

        Task { await viewModel.prepare() }
        Task { await updateChecker.check() } // silent background check at launch
    }

    // MARK: Setup

    private func configurePopover() {
        // Persistent: the popover stays open across app switches, Space switches,
        // record clicks, and transcription. It closes only on the menu bar icon or
        // the ✕ button. (`.transient` would dismiss it on any focus change.)
        popover.behavior = .applicationDefined
        let rootView = PopoverView()
            .environment(viewModel)
            .environment(updateChecker)
        let hosting = NSHostingController(rootView: rootView)
        hosting.sizingOptions = [.preferredContentSize] // let the SwiftUI content size the popover
        popover.contentViewController = hosting
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.image = micImage(filled: false)
        button.action = #selector(togglePopover)
        button.target = self
    }

    private func registerHotkey() {
        hotKey = GlobalHotKey(keyCode: GlasnikShortcut.keyCode, modifiers: GlasnikShortcut.modifiers) { [weak self] in
            // The Carbon hotkey callback fires on the main thread.
            MainActor.assumeIsolated { self?.handleHotkey() }
        }
        if hotKey == nil {
            Log.app.error("Failed to register global hotkey \(GlasnikShortcut.display, privacy: .public)")
            viewModel.noteHotkeyUnavailable()
        } else {
            Log.app.info("Registered global hotkey \(GlasnikShortcut.display, privacy: .public)")
        }
    }

    // MARK: Actions

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // Keep the popover visible across all Spaces while it's open. (The red menu
        // bar icon is the always-visible recording indicator regardless.)
        if let window = popover.contentViewController?.view.window {
            window.collectionBehavior.insert(.canJoinAllSpaces)
            window.collectionBehavior.insert(.fullScreenAuxiliary)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Hotkey fired: make sure there's visible feedback, then toggle recording.
    private func handleHotkey() {
        if !popover.isShown { showPopover() }
        viewModel.toggleRecording()
    }

    // MARK: Status icon

    private func updateStatusIcon(for state: AppState) {
        guard let button = statusItem.button else { return }
        if case .recording = state {
            button.image = micImage(filled: true)
            button.contentTintColor = .systemRed
        } else {
            button.image = micImage(filled: false)
            button.contentTintColor = nil
        }
    }

    private func micImage(filled: Bool) -> NSImage? {
        let image = NSImage(
            systemSymbolName: filled ? "mic.fill" : "mic",
            accessibilityDescription: "Glasnik"
        )
        image?.isTemplate = true
        return image
    }
}
