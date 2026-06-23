import SwiftUI

/// The popover UI — clean, native macOS styling. Fixed width with a height-bounded,
/// scrollable result so it never grows past the screen. Binds to the shared
/// `RecorderViewModel` and `UpdateChecker` from the environment.
struct PopoverView: View {
    @Environment(RecorderViewModel.self) private var vm
    @Environment(UpdateChecker.self) private var updater

    private let popoverWidth: CGFloat = 440
    private let resultMaxHeight: CGFloat = 240

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: popoverWidth)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.circle.fill")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text("Glasnik").font(.headline)
                Text("Serbian → English").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button { vm.onRequestClose?() } label: {
                Image(systemName: "xmark.circle.fill").font(.body).foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: Content

    private var content: some View {
        VStack(spacing: 14) {
            recordButton
            statusLine
            if let notice = vm.notice { noticeView(notice) }
            if case .done = vm.state {
                resultCard
                copyBar
                if let hint = vm.hint { hintView(hint) }
            }
            if case .error(let error) = vm.state { errorView(error) }
            if updater.updateAvailable { updateBanner }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
    }

    // MARK: Record button

    private var recordButton: some View {
        Button(action: { vm.toggleRecording() }) {
            ZStack {
                Circle()
                    .stroke(buttonColor.opacity(0.4), lineWidth: 3)
                    .frame(width: 98, height: 98)
                    .scaleEffect(vm.isRecording ? 1 + vm.level * 0.4 : 1)
                    .opacity(vm.isRecording ? 1 : 0)
                    .animation(.easeOut(duration: 0.1), value: vm.level)
                Circle()
                    .fill(buttonColor.gradient)
                    .frame(width: 76, height: 76)
                    .shadow(color: buttonColor.opacity(0.35), radius: vm.isRecording ? 12 : 5)
                if vm.isBusy {
                    ProgressView().controlSize(.large).tint(.white)
                } else {
                    Image(systemName: vm.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(height: 100)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!vm.canRecord)
        .opacity(vm.canRecord ? 1 : 0.5)
    }

    private var buttonColor: Color { vm.isRecording ? .red : .accentColor }

    // MARK: Status

    private var statusLine: some View {
        Group {
            if vm.showCopiedConfirmation {
                Label("Copied to clipboard", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Text(statusText).foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.2), value: vm.showCopiedConfirmation)
    }

    private var statusText: String {
        switch vm.state {
        case .preparing: return "Preparing model… (one-time download)"
        case .idle: return "Tap to record · \(GlasnikShortcut.display)"
        case .recording: return "Recording… tap to stop"
        case .transcribing: return "Transcribing…"
        case .translating: return "Translating…"
        case .done: return "Done"
        case .error: return "Something went wrong"
        }
    }

    // MARK: Notice

    private func noticeView(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.orange)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    // MARK: Result (Serbian left · English right, scrollable, height-bounded)

    private var resultCard: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 14) {
                resultColumn(title: "SERBIAN",
                             text: vm.serbianText.isEmpty ? "—" : vm.serbianText,
                             font: .subheadline,
                             color: .secondary)
                Divider()
                resultColumn(title: "ENGLISH",
                             text: vm.englishText,
                             font: .callout,
                             color: .primary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxHeight: resultMaxHeight)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
    }

    private func resultColumn(title: String, text: String, font: Font, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
            Text(text)
                .font(font)
                .foregroundStyle(color)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var copyBar: some View {
        HStack(spacing: 8) {
            Button { vm.copyEnglish() } label: {
                Label("Copy English", systemImage: "doc.on.doc")
            }
            .controlSize(.small)
            Spacer()
            if vm.translationSource == .ollama {
                Label("polished by Ollama", systemImage: "sparkles")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .labelStyle(.titleAndIcon)
            }
        }
    }

    // MARK: Hint (offline fallback)

    private func hintView(_ hint: AppHint) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(hint.message).font(.caption).foregroundStyle(.secondary)
                if let action = hint.action {
                    Button(action.label) { vm.performRecoveryAction(action) }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Error

    private func errorView(_ error: AppError) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                Text(error.message).font(.callout)
                Spacer(minLength: 0)
            }
            HStack {
                if let action = error.action {
                    Button(action.label) { vm.performRecoveryAction(action) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
                Button("Retry") { vm.retryAfterError() }.controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.red.opacity(0.1)))
    }

    // MARK: Update banner

    private var updateBanner: some View {
        Button { updater.openReleasePage() } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.circle.fill")
                Text("Update available — v\(updater.availableVersion ?? "")").fontWeight(.medium)
                Spacer(minLength: 0)
                Text("Download").foregroundStyle(Color.accentColor)
            }
            .font(.caption)
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.12)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open the latest release on GitHub")
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Text(GlasnikShortcut.display).font(.caption2).foregroundStyle(.secondary)
            Spacer()
            if updater.isChecking { ProgressView().controlSize(.mini) }
            Button { Task { await updater.check(silent: false) } } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Check for updates")
            .disabled(updater.isChecking)
            Button { NSApplication.shared.terminate(nil) } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Quit Glasnik")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
