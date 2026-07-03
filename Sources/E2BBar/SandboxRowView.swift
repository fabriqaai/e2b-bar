import SwiftUI

struct SandboxRowView: View {
    let sandbox: E2BSandbox
    let metrics: SandboxMetricSummary?
    let copy: () -> Void

    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: iconName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 16, height: 18)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(sandbox.displayName)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(MenuHighlightStyle.primary(isHighlighted))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 8)

                    Text(sandbox.state.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusTextColor)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    MetricBadge(title: "CPU", value: metrics?.cpuBadgeValue ?? "\(sandbox.cpuCount)c")
                    MetricBadge(title: "MEM", value: metrics?.memoryBadgeValue ?? Self.megabytes(sandbox.memoryMB))
                    MetricBadge(title: "DSK", value: metrics?.diskBadgeValue ?? Self.megabytes(sandbox.diskSizeMB))

                    if let endAt = sandbox.endAt {
                        Text("expires \(Self.relative(endAt))")
                            .monospacedDigit()
                            .padding(.leading, 1)
                    }
                }
                .font(.caption)
                .foregroundStyle(MenuHighlightStyle.secondary(isHighlighted))
                .lineLimit(1)

                HStack(spacing: 7) {
                    Text(sandbox.short(sandbox.sandboxID))
                        .fontDesign(.monospaced)

                    if let metadataSummary = sandbox.metadataSummary {
                        Text(metadataSummary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .font(.caption2)
                .foregroundStyle(MenuHighlightStyle.tertiary(isHighlighted))
                .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture(perform: copy)
    }

    private var iconName: String {
        switch sandbox.state {
        case .running:
            "play.circle"
        case .paused:
            "pause.circle"
        case .unknown:
            "questionmark.circle"
        }
    }

    private var iconColor: Color {
        switch sandbox.state {
        case .running:
            .green
        case .paused:
            .orange
        case .unknown:
            .secondary
        }
    }

    private var statusTextColor: Color {
        isHighlighted ? .white.opacity(0.86) : iconColor
    }

    private static func relative(_ date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    private static func megabytes(_ value: Int) -> String {
        MetricFormatting.bytes(Int64(value) * 1024 * 1024)
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}

private struct MetricBadge: View {
    let title: String
    let value: String

    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        HStack(spacing: 3) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(MenuHighlightStyle.tertiary(isHighlighted))
            Text(value)
                .font(.caption.monospacedDigit().weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 5)
        .background(background, in: RoundedRectangle(cornerRadius: 5))
    }

    private var background: Color {
        isHighlighted ? .white.opacity(0.14) : .secondary.opacity(0.1)
    }
}
