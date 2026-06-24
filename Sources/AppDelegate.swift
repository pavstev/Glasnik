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
    private var escapeMonitor: Any?

    /// JSON-backed translation history, shared with the popover's HistoryView.
    private let historyStore = HistoryStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        configurePopover()
        configureStatusItem()
        registerHotkey()
        installCancelShortcut()

        viewModel.onStateChange = { [weak self] state in
            self?.updateStatusIcon(for: state)
            // A download that finished while busy installs once we're safely idle.
            self?.updateChecker.installIfReady()
        }
        viewModel.onRequestClose = { [weak self] in
            self?.popover.performClose(nil)
        }
        viewModel.onLevelChange = { [weak self] levels in
            self?.updateWaveform(levels)
        }

        // The updater may swap the running bundle — only ever while idle, never mid-record.
        updateChecker.canInstallNow = { [weak self] in
            guard let vm = self?.viewModel else { return false }
            return !vm.isBusy && !vm.isRecording
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
        // Šapat's popover wears its own warm copper-on-stone identity, so pin it to a
        // dark appearance regardless of the system setting (the views are authored for it).
        popover.appearance = NSAppearance(named: .darkAqua)
        viewModel.history = historyStore
        let rootView = PopoverView()
            .environment(viewModel)
            .environment(updateChecker)
            .environment(historyStore)
        let hosting = NSHostingController(rootView: rootView)
        hosting.sizingOptions = [.preferredContentSize] // let the SwiftUI content size the popover
        popover.contentViewController = hosting
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.image = glyphImage()
        button.action = #selector(togglePopover)
        button.target = self
    }

    private func registerHotkey() {
        hotKey = GlobalHotKey(keyCode: SapatShortcut.keyCode, modifiers: SapatShortcut.modifiers) { [weak self] in
            // The Carbon hotkey callback fires on the main thread.
            MainActor.assumeIsolated { self?.handleHotkey() }
        }
        if hotKey == nil {
            Log.app.error("Failed to register global hotkey \(SapatShortcut.display, privacy: .public)")
            viewModel.noteHotkeyUnavailable()
        } else {
            Log.app.info("Registered global hotkey \(SapatShortcut.display, privacy: .public)")
        }
    }

    /// Escape cancels an in-progress recording (discarding it), or dismisses the popover
    /// when it's focused and no text field is being edited. A *local* monitor only fires
    /// while Šapat is the active app, so it never hijacks Escape system-wide.
    private func installCancelShortcut() {
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53, let self else { return event } // 53 = Escape
            // The local monitor fires on the main thread; touch main-actor state safely.
            let handled = MainActor.assumeIsolated { () -> Bool in
                if self.viewModel.isRecording {
                    self.viewModel.cancelRecording()
                    return true
                }
                let window = self.popover.contentViewController?.view.window
                if self.popover.isShown, event.window === window,
                   !(window?.firstResponder is NSText) {
                    self.popover.performClose(nil)
                    return true
                }
                return false
            }
            return handled ? nil : event // consume only when we acted
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
            button.image = glyphImage()
            button.contentTintColor = .systemRed
        } else {
            button.image = glyphImage()
            button.contentTintColor = nil
        }
    }

    /// The bold Cyrillic Ш (Šapat), drawn as a monochrome template so the menu bar tints
    /// it (default for idle, red while recording — until the waveform takes over).
    private func glyphImage() -> NSImage {
        let size = NSSize(width: 18, height: 16)
        let image = NSImage(size: size)
        image.lockFocus()
        let font = NSFont.systemFont(ofSize: 14, weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let glyph = NSAttributedString(string: Brand.monogram, attributes: attributes)
        let textSize = glyph.size()
        glyph.draw(at: NSPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2))
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    // MARK: Menu-bar waveform (while recording)

    private func updateWaveform(_ levels: [Double]) {
        guard let button = statusItem.button else { return }
        button.image = waveformImage(levels)
        button.contentTintColor = .systemRed
    }

    private func waveformImage(_ levels: [Double]) -> NSImage {
        let size = NSSize(width: 22, height: 16)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.black.setFill()
        let barWidth: CGFloat = 1.6
        let gap: CGFloat = 1.4
        let count = max(levels.count, 1)
        let totalWidth = CGFloat(count) * barWidth + CGFloat(count - 1) * gap
        var x = (size.width - totalWidth) / 2
        for level in levels {
            let barHeight = max(2, CGFloat(level) * size.height)
            let rect = NSRect(x: x, y: (size.height - barHeight) / 2, width: barWidth, height: barHeight)
            NSBezierPath(roundedRect: rect, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
            x += barWidth + gap
        }
        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}
