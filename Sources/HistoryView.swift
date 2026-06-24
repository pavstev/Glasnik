import AppKit
import SwiftUI

/// In-popover searchable history of past translations (JSON-backed HistoryStore),
/// styled to Šapat's copper-on-stone `Theme`. Rows are concise and tap-to-expand:
/// collapsed shows a one-line preview, expanded reveals the full text + actions.
struct HistoryView: View {
    @Environment(HistoryStore.self) private var store
    @State private var search = ""
    /// Ids of rows currently expanded. Held here (not per-row @State) so expansion
    /// survives search-filtering and LazyVStack recycling.
    @State private var expanded: Set<UUID> = []

    var body: some View {
        VStack(spacing: Theme.s2) {
            searchField
            if filtered.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: Theme.s2) {
                        ForEach(filtered) { item in
                            HistoryRow(
                                item: item,
                                isExpanded: expanded.contains(item.id),
                                onToggle: { toggle(item) },
                                onCopy: { copy(item.english) },
                                onDelete: { delete(item) }
                            )
                        }
                    }
                    .padding(.horizontal, Theme.s4)
                    .padding(.bottom, Theme.s4)
                }
                .frame(maxHeight: 300)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, filtered.isEmpty ? Theme.s4 : 0)
        // Drop expansion state for rows the search filtered out, so they don't
        // reappear pre-expanded later.
        .onChange(of: search) { _, _ in
            expanded.formIntersection(Set(filtered.map(\.id)))
        }
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

    private func toggle(_ item: TranslationRecord) {
        withAnimation(.snappy) {
            if expanded.contains(item.id) { expanded.remove(item.id) }
            else { expanded.insert(item.id) }
        }
    }

    private func delete(_ item: TranslationRecord) {
        expanded.remove(item.id)
        withAnimation(.snappy) { store.delete(item) }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// One concise, tap-to-expand history entry.
///
/// Collapsed: a single English preview line + a small `source · date` meta line,
/// fronted by a chevron that rotates when open. Tapping anywhere toggles it.
/// Expanded: full selectable English, the Serbian source, and copy/delete actions.
private struct HistoryRow: View {
    let item: TranslationRecord
    let isExpanded: Bool
    let onToggle: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void

    @State private var justCopied = false

    private var sourceIcon: String { item.source == "LM Studio" ? "sparkles" : "waveform" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — the whole thing is the toggle. When collapsed it carries a
            // one-line preview; when expanded it steps back to just the chevron + date
            // so the full, selectable text can live (un-tappable) in the detail block.
            Button(action: onToggle) {
                HStack(alignment: .top, spacing: Theme.s2) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.copperLight)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: Theme.s1) {
                        if isExpanded {
                            metaLine(compact: false)
                        } else {
                            Text(item.english)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            metaLine(compact: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(item.english)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint(isExpanded ? "Collapse details" : "Expand details")

            // Detail — revealed on expand. Full English lives here (outside the toggle
            // Button) so it is actually selectable; the Serbian source follows.
            if isExpanded {
                VStack(alignment: .leading, spacing: Theme.s2) {
                    Text(item.english)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if !item.serbian.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.s1) {
                            Text("Serbian")
                                .font(.system(size: 10, weight: .medium))
                                .textCase(.uppercase)
                                .foregroundStyle(Theme.textTertiary)
                            Text(item.serbian)
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    Rectangle()
                        .fill(Theme.hairline)
                        .frame(height: 0.5)

                    HStack(spacing: Theme.s3) {
                        Spacer()
                        Button(action: copy) {
                            Label(justCopied ? "Copied" : "Copy",
                                  systemImage: justCopied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 11))
                                .labelStyle(.titleAndIcon)
                                .foregroundStyle(justCopied ? Theme.positive : Theme.copperLight)
                        }
                        .buttonStyle(.plain)
                        .help("Copy English")

                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .help("Delete")
                    }
                }
                .padding(.top, Theme.s2)
                .padding(.leading, Theme.s4 + Theme.s1) // align under the preview text
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(Theme.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(Theme.rSmall)
        // Auto-clear the transient "Copied" confirmation.
        .task(id: justCopied) {
            guard justCopied else { return }
            try? await Task.sleep(for: .seconds(1.4))
            withAnimation(.snappy) { justCopied = false }
        }
    }

    /// `source-icon · relative-date` (compact) or absolute timestamp (expanded).
    private func metaLine(compact: Bool) -> some View {
        HStack(spacing: Theme.s1 + 2) {
            Image(systemName: sourceIcon)
                .font(.system(size: 10))
                .foregroundStyle(Theme.textTertiary)
            Text(compact
                 ? item.date.formatted(.relative(presentation: .named))
                 : item.date.formatted(.dateTime.month().day().hour().minute()))
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private func copy() {
        onCopy()
        withAnimation(.snappy) { justCopied = true }
    }
}
