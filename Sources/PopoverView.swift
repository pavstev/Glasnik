import SwiftUI

/// The popover UI — Šapat's warm copper-on-stone identity. Fixed width, content-driven
/// height, with a height-bounded scrollable result. Binds to the shared
/// `RecorderViewModel` and `UpdateChecker` from the environment.
///
/// The hosting popover is pinned to a dark appearance in `AppDelegate`, so this view is
/// authored against the `Theme` palette rather than system semantic colors.
struct PopoverView: View {
    @Environment(RecorderViewModel.self) private var vm
    @Environment(UpdateChecker.self) private var updater

    private let resultMaxHeight: CGFloat = 220

    @State private var tab: Tab = .record
    private enum Tab: Hashable { case record, history }

    var body: some View {
        VStack(spacing: 0) {
            header
            tabBar
            Group {
                if tab == .record { recordContent } else { HistoryView() }
            }
            footer
        }
        .frame(width: Theme.popoverWidth)
        .background(Theme.stone)
        .tint(Theme.copper)
        .environment(\.colorScheme, .dark)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: Theme.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.rSmall, style: .continuous).fill(Theme.copper)
                Text(Brand.monogram).font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.stone)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 1) {
                Text(Brand.displayName).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                HStack(spacing: 4) {
                    Text("Српски").foregroundStyle(Theme.textSecondary)
                    Image(systemName: "arrow.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.copperLight)
                    Text("English").foregroundStyle(Theme.textSecondary)
                }
                .font(.caption2)
            }

            Spacer()

            SettingsLink {
                Image(systemName: "gearshape").font(.system(size: 15))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.textTertiary)
            .help("Settings")

            Button { vm.onRequestClose?() } label: {
                Image(systemName: "xmark").font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.textTertiary)
            .help("Close")
        }
        .padding(Theme.s4)
    }

    // MARK: Tab bar

    private var tabBar: some View {
        HStack(spacing: Theme.s2 - 2) {
            tabButton(.record, "Record")
            tabButton(.history, "History")
        }
        .padding(.horizontal, Theme.s4)
        .padding(.bottom, Theme.s3)
    }

    private func tabButton(_ which: Tab, _ title: String) -> some View {
        let active = tab == which
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { tab = which }
        } label: {
            Text(title)
                .font(.system(size: 13, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? Theme.stone : Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: Theme.rSmall, style: .continuous)
                        .fill(active ? Theme.copper : Theme.copperLight.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: Record content

    private var recordContent: some View {
        VStack(spacing: Theme.s4) {
            recordButton
            statusLine
            preparingProgress
            if let notice = vm.notice { noticeView(notice) }
            if case .done = vm.state {
                resultCard
                if let hint = vm.hint { hintView(hint) }
            }
            if case .error(let error) = vm.state { errorView(error) }
            updateSection
        }
        .padding(.horizontal, Theme.s4)
        .padding(.bottom, Theme.s4)
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.2), value: vm.state)
    }

    // MARK: Record button (hero)

    private var recordButton: some View {
        Button(action: { vm.toggleRecording() }) {
            ZStack {
                Circle().fill(Theme.copperLight.opacity(0.10)).frame(width: 96, height: 96)
                Circle()
                    .stroke(buttonColor.opacity(0.4), lineWidth: 3)
                    .frame(width: 96, height: 96)
                    .scaleEffect(vm.isRecording ? 1 + vm.level * 0.35 : 1)
                    .opacity(vm.isRecording ? 1 : 0)
                    .animation(.easeOut(duration: 0.1), value: vm.level)
                Circle()
                    .fill(buttonColor)
                    .frame(width: 72, height: 72)
                    .shadow(color: buttonColor.opacity(0.4), radius: vm.isRecording ? 12 : 6)
                if vm.isBusy {
                    ProgressView().controlSize(.large).tint(Theme.textPrimary)
                } else {
                    Image(systemName: vm.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 27, weight: .semibold))
                        .foregroundStyle(vm.isRecording ? .white : Theme.stone)
                }
            }
            .frame(height: 100)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!vm.canRecord)
        .opacity(vm.canRecord ? 1 : 0.55)
        .padding(.top, Theme.s2)
    }

    private var buttonColor: Color { vm.isRecording ? Theme.recording : Theme.copper }

    // MARK: Status (height-locked so the layout never jumps)

    private var statusLine: some View {
        Group {
            if vm.showCopiedConfirmation {
                Label("Copied to clipboard", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.positive)
            } else {
                Text(statusText).foregroundStyle(Theme.textSecondary)
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity)
        .frame(height: 20)
        .animation(.easeInOut(duration: 0.2), value: vm.showCopiedConfirmation)
    }

    private var statusText: String {
        switch vm.state {
        case .preparing(let progress):
            if let progress, progress < 1 { return "Downloading model… \(Int(progress * 100))%" }
            return "Loading model…"
        case .idle: return "Tap to record · \(SapatShortcut.display)"
        case .recording: return "Recording \(recordingClock(vm.recordingDuration)) · Esc to cancel"
        case .transcribing: return "Transcribing…"
        case .translating: return "Refining…"
        case .done: return "Done"
        case .error: return "Something went wrong"
        }
    }

    private func recordingClock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// First-run model download — a determinate bar with a one-time-cost caption.
    @ViewBuilder private var preparingProgress: some View {
        if case .preparing(let progress) = vm.state, let progress, progress < 1 {
            VStack(spacing: Theme.s1 + 2) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(Theme.copper)
                Text("First run downloads the speech model (~2.9 GB) — one time.")
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(Theme.s3)
            .cardSurface(Theme.rSmall)
            .transition(.opacity)
        }
    }

    // MARK: Notice (transient)

    private func noticeView(_ text: String) -> some View {
        HStack(spacing: Theme.s2) {
            Image(systemName: "exclamationmark.bubble").foregroundStyle(Theme.copperLight)
            Text(text).foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 0)
        }
        .font(.callout)
        .padding(Theme.s3)
        .cardSurface(Theme.rSmall)
    }

    // MARK: Result (СРПСКИ left · ENGLISH right, scrollable, height-bounded)

    private var resultCard: some View {
        VStack(spacing: 0) {
            ScrollView {
                HStack(alignment: .top, spacing: Theme.s3) {
                    resultColumn(title: "СРПСКИ",
                                 text: vm.serbianText.isEmpty ? "—" : vm.serbianText,
                                 font: .system(size: 13),
                                 color: Theme.textSecondary)
                    Rectangle().fill(Theme.hairline).frame(width: 1)
                    resultColumn(title: "ENGLISH",
                                 text: vm.englishText,
                                 font: .system(size: 14),
                                 color: Theme.textPrimary)
                }
                .padding(Theme.s3)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxHeight: resultMaxHeight)

            copyBar
                .padding(.horizontal, Theme.s3)
                .padding(.vertical, Theme.s2 + 2)
                .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
        }
        .cardSurface()
    }

    private func resultColumn(title: String, text: String, font: Font, color: Color) -> some View {
        VStack(alignment: .leading, spacing: Theme.s1 + 2) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.textTertiary)
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
        HStack(spacing: Theme.s2) {
            if vm.translationSource == .lmStudio {
                Label("refined by LM Studio", systemImage: "sparkles")
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
                    .labelStyle(.titleAndIcon)
            }
            Spacer(minLength: 0)
            Button { vm.copyEnglish() } label: {
                Label("Copy English", systemImage: "doc.on.doc")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.stone)
                    .padding(.horizontal, Theme.s3)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Theme.copperLight))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Hint (offline fallback) — same card family as notice/error

    private func hintView(_ hint: AppHint) -> some View {
        HStack(alignment: .top, spacing: Theme.s2) {
            Image(systemName: "info.circle").foregroundStyle(Theme.copperLight)
            VStack(alignment: .leading, spacing: Theme.s1) {
                Text(hint.message).font(.caption).foregroundStyle(Theme.textSecondary)
                if let action = hint.action {
                    Button(action.label) { vm.performRecoveryAction(action) }
                        .buttonStyle(.plain)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.copperLight)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.s3)
        .cardSurface(Theme.rSmall)
    }

    // MARK: Error

    private func errorView(_ error: AppError) -> some View {
        VStack(alignment: .leading, spacing: Theme.s2 + 2) {
            HStack(alignment: .top, spacing: Theme.s2) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.recording)
                Text(error.message).font(.callout).foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
            }
            HStack(spacing: Theme.s2) {
                if let action = error.action {
                    Button(action.label) { vm.performRecoveryAction(action) }
                        .controlSize(.small)
                }
                Button("Retry") { vm.retryAfterError() }.controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.s3)
        .background(
            RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous).fill(Theme.recording.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous).strokeBorder(Theme.recording.opacity(0.25), lineWidth: 0.5)
        )
    }

    // MARK: Update section (reflects the in-app updater lifecycle)

    @ViewBuilder private var updateSection: some View {
        switch updater.phase {
        case .idle:
            EmptyView()
        case .available(let version):
            updateRow(icon: "arrow.down.circle", text: "Update available — v\(version)",
                      actionLabel: "Download") { updater.downloadNow() }
        case .downloading(let version):
            updateProgressRow("Downloading update — v\(version)…")
        case .readyToInstall(let version):
            updateRow(icon: "arrow.up.circle.fill", text: "Update v\(version) ready",
                      actionLabel: "Restart to update") { updater.install() }
        case .installing(let version):
            updateProgressRow("Installing v\(version) — relaunching…")
        case .failed(let message):
            updateRow(icon: "exclamationmark.triangle", text: message,
                      actionLabel: "Retry") { updater.downloadNow() }
        }
    }

    private func updateProgressRow(_ text: String) -> some View {
        HStack(spacing: Theme.s2) {
            ProgressView().controlSize(.small)
            Text(text).font(.caption).foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(Theme.s3)
        .cardSurface(Theme.rSmall)
    }

    private func updateRow(icon: String, text: String, actionLabel: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: Theme.s2) {
            Image(systemName: icon).foregroundStyle(Theme.copperLight)
            Text(text)
                .font(.caption)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(actionLabel, action: action)
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.stone)
                .padding(.horizontal, Theme.s3)
                .padding(.vertical, 5)
                .background(Capsule().fill(Theme.copperLight))
        }
        .padding(Theme.s3)
        .background(
            RoundedRectangle(cornerRadius: Theme.rSmall, style: .continuous).fill(Theme.copperWash)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.rSmall, style: .continuous).strokeBorder(Theme.copperLight.opacity(0.25), lineWidth: 0.5)
        )
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: Theme.s3) {
            updateStatusPill
            Spacer()
            if updater.isChecking { ProgressView().controlSize(.mini) }
            Button { Task { await updater.check(silent: false) } } label: {
                Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.textTertiary)
            .help("Check for updates")
            .disabled(updater.isChecking)
            Button { NSApplication.shared.terminate(nil) } label: {
                Image(systemName: "power").font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.textTertiary)
            .help("Quit \(Brand.displayName)")
        }
        .padding(.horizontal, Theme.s4)
        .padding(.vertical, Theme.s2 + 2)
        .background(Theme.stoneSunken)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
    }

    @ViewBuilder private var updateStatusPill: some View {
        HStack(spacing: 5) {
            if updater.updateAvailable {
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(Theme.copperLight)
                Text(updater.pendingVersion.map { "v\($0) pending" } ?? "Update pending")
            } else {
                Image(systemName: "checkmark.circle").foregroundStyle(Theme.positive)
                Text(updater.automaticUpdates ? "Up to date · auto-updates on" : "Up to date")
            }
        }
        .font(.caption2)
        .foregroundStyle(Theme.textTertiary)
    }
}
