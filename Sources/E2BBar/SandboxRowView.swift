import SwiftUI

struct SandboxRowView: View {
    let sandbox: E2BSandbox
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

                HStack(spacing: 7) {
                    Text(sandbox.resourceSummary)
                        .fontWeight(.semibold)
                        .monospacedDigit()

                    if let endAt = sandbox.endAt {
                        Text("expires \(Self.relative(endAt))")
                            .monospacedDigit()
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

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}
