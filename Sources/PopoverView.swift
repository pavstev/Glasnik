import SwiftUI

/// The popover UI. 340pt wide; height is intrinsic. Binds to the shared
/// `RecorderViewModel` and `UpdateChecker` from the environment.
struct PopoverView: View {
    @Environment(RecorderViewModel.self) private var vm
    @Environment(UpdateChecker.self) private var updater

    var body: some View {
        VStack(spacing: 14) {
            header
            recordButton
            statusLine

            if let notice = vm.notice {
                Text(notice)
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            if case .done = vm.state {
                transcriptView
                if let hint = vm.hint {
                    hintView(hint)
                }
            }

            if case .error(let error) = vm.state {
                errorView(error)
            }

            if updater.updateAvailable {
                updateBanner
            }

            footer
        }
        .padding(16)
        .frame(width: 340)
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 2) {
            Text("Glasnik").font(.headline)
            Text("Serbian → English").font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Record button

    private var recordButton: some View {
        Button(action: { vm.toggleRecording() }) {
            ZStack {
                Circle()
                    .fill(buttonColor.opacity(0.18))
                    .frame(width: 100, height: 100)
                    .scaleEffect(vm.isRecording ? 1 + vm.level * 0.5 : 1)
                    .animation(.easeOut(duration: 0.08), value: vm.level)

                Circle()
                    .fill(buttonColor)
                    .frame(width: 74, height: 74)

                if vm.isBusy {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                } else {
                    Image(systemName: vm.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 100, height: 100)
        }
        .buttonStyle(.plain)
        .disabled(!vm.canRecord)
        .opacity(vm.canRecord ? 1 : 0.55)
    }

    private var buttonColor: Color {
        vm.isRecording ? .red : .accentColor
    }

    // MARK: Status line

    private var statusLine: some View {
        HStack(spacing: 6) {
            Text(statusText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if vm.showCopiedConfirmation {
                Label("Copied", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                    .labelStyle(.titleAndIcon)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut, value: vm.showCopiedConfirmation)
    }

    private var statusText: String {
        switch vm.state {
        case .preparing(let progress):
            if let progress {
                return "Downloading model… \(Int(progress * 100))%"
            }
            return "Preparing model… (first run downloads ~250 MB)"
        case .idle:
            return "Tap the mic, or press \(GlasnikShortcut.display)"
        case .recording:
            return "Recording… tap to stop"
        case .transcribing:
            return "Transcribing…"
        case .translating:
            return "Translating…"
        case .done:
            return vm.translationSource == .ollama ? "Done · polished by Ollama" : "Done"
        case .error:
            return "Something went wrong"
        }
    }

    // MARK: Transcript

    private var transcriptView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !vm.serbianText.isEmpty {
                Text(vm.serbianText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Divider()
            }
            Text(vm.englishText)
                .font(.title3)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .textBackgroundColor)))
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Error

    private func errorView(_ error: AppError) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                Text(error.message).font(.callout).foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            HStack {
                if let action = error.action {
                    Button(action.label) { vm.performRecoveryAction(action) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
                Button("Retry") { vm.retryAfterError() }
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.red.opacity(0.08)))
    }

    // MARK: Update banner

    private var updateBanner: some View {
        Button { updater.openReleasePage() } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.circle.fill")
                Text("Update available — v\(updater.availableVersion ?? "")")
                    .fontWeight(.medium)
                Spacer(minLength: 0)
                Text("Download").foregroundStyle(.blue)
            }
            .font(.caption)
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.12)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open the latest release on GitHub")
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Text("Shortcut \(GlasnikShortcut.display)")
                .foregroundStyle(.secondary)
                .help("Global shortcut to start/stop recording")
            Spacer()
            Button { Task { await updater.check(silent: false) } } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.borderless)
            .help("Check for updates")
            .disabled(updater.isChecking)
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help("Quit Glasnik")
        }
        .font(.caption)
    }
}
