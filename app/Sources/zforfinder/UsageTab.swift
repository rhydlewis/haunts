import SwiftUI
import AppKit
import HauntsCore
import ZFFEngine

// MARK: - Usage

/// Preferences → Usage. A passive renderer over `model.usageStats` (the pure
/// `UsageStats` aggregation): one warm headline stat, a ranked top-10, and a
/// graceful empty state. Restraint is the brief — a settings pane, not a
/// dashboard: ember appears exactly once when populated (the big total).
struct UsageTab: View {
    @ObservedObject var model: PreferencesModel

    var body: some View {
        Group {
            if let stats = model.usageStats, !stats.isEmpty {
                populated(stats)
            } else {
                EmptyUsageState(hotkey: model.hotkeyDisplay)
            }
        }
        .onAppear { model.refreshUsageStats() }
    }

    // MARK: Populated

    private func populated(_ stats: UsageStats) -> some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(stats.leadText(now: Date()))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(stats.countText())
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.ember)
                    if let cadence = stats.cadenceText() {
                        Text(cadence)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                let rows = Array(stats.topLocations.enumerated())
                ForEach(rows, id: \.element.id) { idx, row in
                    UsageRowView(rank: idx + 1, row: row, showDate: stats.hasAnyDate)
                }
            } header: {
                Text("Your top haunts")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Everything here stays on your Mac. Haunts never phones home.")
                    Text("Reset these numbers under Ranking → Reset Learned Data.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Row

private struct UsageRowView: View {
    let rank: Int
    let row: UsageStats.Row
    let showDate: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(rank == 1 ? Color.ember : .secondary)
                .frame(width: 22, alignment: .trailing)

            Text(displayPath(row.path))
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(row.jumpCount, format: .number)
                .font(.system(.body, design: .rounded).monospacedDigit())
                .foregroundStyle(.primary)
                .frame(minWidth: 44, alignment: .trailing)

            if showDate {
                Text(relativeDate(row.lastJumped))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 64, alignment: .trailing)
            }
        }
    }

    /// Abbreviated relative date ("2h ago"); blank when this row has no date but
    /// the column is shown because a sibling does.
    private func relativeDate(_ date: Date?) -> String {
        guard let date else { return "" }
        return UsageRowView.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
}

// MARK: - Empty state

/// Shown on a fresh install (or right after Reset Learned Data) when no explicit
/// jumps have been recorded. Mirrors the About tab's centred rhythm; the ghost is
/// muted (no ember tile) and the prompt uses the live hotkey chord.
private struct EmptyUsageState: View {
    let hotkey: String

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(nsImage: GhostIcon.menuBarImage(size: 56))
                .renderingMode(.template)
                .foregroundStyle(.secondary)
                .opacity(0.55)

            Text("No haunts yet")
                .font(.system(size: 19, weight: .semibold))

            Text("Hit \(hotkey), find a folder, and jump in. The places you keep coming back to will show up here.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 360)

            Text("Everything stays on your Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
