import SwiftUI

struct UsageMenuView: View {
    let usage: TeamUsageSummary?
    let usageError: String?
    let hasTeamID: Bool
    let isRefreshing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Usage")
                    .font(.callout.weight(.semibold))
                Spacer()
                Text(self.badgeText)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(self.hasTeamID ? .green : .secondary)
                    .padding(.vertical, 3)
                    .padding(.horizontal, 7)
                    .background((self.hasTeamID ? Color.green : Color.secondary).opacity(0.14), in: Capsule())
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                UsageTile(title: "Live concurrent", value: self.liveConcurrent)
                UsageTile(title: "Start rate", value: self.startRate)
                UsageTile(title: "Peak concurrent", value: self.peakConcurrent)
                UsageTile(title: "Peak start rate", value: self.peakStartRate)
            }

            VStack(alignment: .leading, spacing: 8) {
                UsageTrendRow(
                    title: "Concurrent, 24h",
                    caption: self.concurrentTrendCaption,
                    values: self.usage?.concurrentSeries ?? [],
                    color: Self.concurrentColor
                )
                UsageTrendRow(
                    title: "Starts/min, 24h",
                    caption: self.startRateTrendCaption,
                    values: self.usage?.startRateSeries ?? [],
                    color: Self.startRateColor
                )
            }

            Text(self.footerLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 360, alignment: .leading)
    }

    private var badgeText: String {
        if self.isRefreshing { return "LIVE" }
        return self.hasTeamID ? "READY" : "SETUP"
    }

    private var liveConcurrent: String {
        guard let usage else { return "--" }
        return "\(usage.latestConcurrent)"
    }

    private var peakConcurrent: String {
        guard let usage else { return "--" }
        return "\(usage.peakConcurrent)"
    }

    private var startRate: String {
        guard let usage else { return "--" }
        return "\(Self.number(usage.latestStartsPerMinute))/min"
    }

    private var peakStartRate: String {
        guard let usage else { return "--" }
        return "\(Self.number(usage.peakStartsPerMinute))/min"
    }

    private var footerLine: String {
        if !self.hasTeamID {
            return "Add a team ID in Settings to load E2B team metrics."
        }
        if let usageError, !usageError.isEmpty {
            return usageError
        }
        if self.usage == nil {
            return "Usage has not been loaded yet."
        }

        return "E2B team metrics · billing and limits live in the dashboard"
    }

    private static func number(_ value: Double) -> String {
        if value >= 10 {
            return String(format: "%.0f", value)
        }
        if value >= 1 {
            return String(format: "%.1f", value)
        }
        return String(format: "%.2f", value)
    }

    private var concurrentTrendCaption: String {
        guard let usage else { return "No samples" }
        return "peak \(usage.peakConcurrent)"
    }

    private var startRateTrendCaption: String {
        guard let usage else { return "No samples" }
        return "peak \(Self.number(usage.peakStartsPerMinute))/min"
    }

    private static let concurrentColor = Color(red: 0.12, green: 0.55, blue: 0.36)
    private static let startRateColor = Color(red: 0.72, green: 0.39, blue: 0.23)
}

private struct UsageTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(self.title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(self.value)
                .font(.caption.monospacedDigit().weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct UsageTrendRow: View {
    let title: String
    let caption: String
    let values: [Double]
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Circle()
                    .fill(self.color.opacity(0.72))
                    .frame(width: 6, height: 6)
                Text(self.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(self.caption)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            MiniUsageBars(values: self.values, color: self.color)
        }
    }
}

private struct MiniUsageBars: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let samples = Array(self.values.suffix(32))
            let maxValue = max(samples.max() ?? 0, 1)
            let barWidth = max(2, (proxy.size.width - CGFloat(max(samples.count - 1, 0)) * 2) / CGFloat(max(samples.count, 1)))

            HStack(alignment: .bottom, spacing: 2) {
                if samples.isEmpty {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.secondary.opacity(0.12))
                        .frame(height: 3)
                } else {
                    ForEach(Array(samples.enumerated()), id: \.offset) { _, value in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(self.color.opacity(0.56))
                            .frame(
                                width: barWidth,
                                height: max(3, proxy.size.height * CGFloat(value / maxValue))
                            )
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottomLeading)
        }
        .frame(height: 18)
        .accessibilityHidden(true)
    }
}
