import AppKit
import SwiftUI

/// In-popover searchable history of past translations (JSON-backed HistoryStore),
/// styled to Šapat's copper-on-stone `Theme`.
struct HistoryView: View {
    @Environment(HistoryStore.self) private var store
    @State private var search = ""

    var body: some View {
        VStack(spacing: Theme.s2) {
            searchField
            if filtered.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: Theme.s2) {
                        ForEach(filtered) { row($0) }
                    }
                    .padding(.horizontal, Theme.s4)
                    .padding(.bottom, Theme.s4)
                }
                .frame(maxHeight: 300)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, filtered.isEmpty ? Theme.s4 : 0)
    }

    private var filtered: [TranslationRecord] {
        guard !search.isEmpty else { return store.records }
        return store.records.filter {
            $0.english.localizedCaseInsensitiveContains(search) ||
            $0.serbian.localizedCaseInsensitiveContains(search)
        }
    }

    private var searchField: some View {
        HStack(spacing: Theme.s2) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
            TextField("Search translations", text: $search)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textPrimary)
            if !search.isEmpty {
                Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.horizontal, Theme.s3)
        .padding(.vertical, Theme.s2)
        .cardSurface(Theme.rSmall)
        .padding(.horizontal, Theme.s4)
        .padding(.top, Theme.s1)
    }

    private var emptyState: some View {
        VStack(spacing: Theme.s2) {
            Image(systemName: store.records.isEmpty ? "waveform" : "magnifyingglass")
                .font(.system(size: 26))
                .foregroundStyle(Theme.textTertiary)
            Text(store.records.isEmpty ? "No translations yet" : "No matches")
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)
            if store.records.isEmpty {
                Text("Hold \(SapatShortcut.display) and speak — your translations land here.")
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.s5)
        .padding(.vertical, 40)
    }

    private func row(_ item: TranslationRecord) -> some View {
        VStack(alignment: .leading, spacing: Theme.s1 + 2) {
            Text(item.english)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !item.serbian.isEmpty {
                Text(item.serbian)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
            }
            HStack(spacing: Theme.s2) {
                Image(systemName: item.source == "Ollama" ? "sparkles" : "waveform")
                    .foregroundStyle(Theme.textTertiary)
                Text(item.date, format: .dateTime.month().day().hour().minute())
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                Button { copy(item.english) } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.plain).foregroundStyle(Theme.textTertiary).help("Copy English")
                Button { store.delete(item) } label: { Image(systemName: "trash") }
                    .buttonStyle(.plain).foregroundStyle(Theme.textTertiary).help("Delete")
            }
            .font(.system(size: 11))
        }
        .padding(Theme.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(Theme.rSmall)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
