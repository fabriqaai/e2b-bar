import SwiftUI

struct MenuHeaderView: View {
    let snapshot: DashboardSnapshot
    let credentialState: CredentialState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("E2B")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(snapshot.runningCount)")
                        .font(.system(size: 32, weight: .semibold, design: .monospaced))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("running sandboxes")
                        .font(.callout.weight(.semibold))
                    Text("\(snapshot.pausedCount) paused - \(snapshot.totalCPU)c - \(Self.memory(snapshot.totalMemoryMB))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StateBadge(snapshot: snapshot)
            }

            HStack(spacing: 8) {
                SummaryTile(title: "Fetched", value: "\(snapshot.totals.fetched)")
                SummaryTile(title: "CPU", value: "\(snapshot.totalCPU)c")
                SummaryTile(title: "Memory", value: Self.memory(snapshot.totalMemoryMB))
                SummaryTile(title: "Next", value: Self.relative(snapshot.nextExpiration))
            }

            if snapshot.error != nil {
                Text(credentialState.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 360, alignment: .leading)
    }

    private static func memory(_ value: Int) -> String {
        guard value >= 1024 else { return "\(value)MB" }
        let gb = Double(value) / 1024.0
        if gb.rounded() == gb {
            return "\(Int(gb))GB"
        }
        return String(format: "%.1fGB", gb)
    }

    private static func relative(_ date: Date?) -> String {
        guard let date else { return "--" }
        return Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}

private struct SummaryTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospacedDigit().weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct StateBadge: View {
    let snapshot: DashboardSnapshot

    var body: some View {
        Text(snapshot.isHealthy ? "OK" : "ERR")
            .font(.caption.weight(.bold))
            .foregroundStyle(snapshot.isHealthy ? .green : .orange)
            .padding(.vertical, 4)
            .padding(.horizontal, 7)
            .background((snapshot.isHealthy ? Color.green : Color.orange).opacity(0.16), in: Capsule())
    }
}
