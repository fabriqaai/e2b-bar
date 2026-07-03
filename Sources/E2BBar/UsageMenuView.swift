import SwiftUI

struct UsageMenuView: View {
    let usage: TeamUsageSummary?
    let usageError: String?
    let hasTeamID: Bool
    let isRefreshing: Bool
    let estimatedDailyCostUSD: Double
    let alertsEnabled: Bool
    let concurrentLimit: Int
    let startsLimit: Int
    let costLimitUSD: Double

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
                UsageTile(title: "24h starts", value: self.startsInWindow)
                UsageTile(title: "Peak concurrent", value: self.peakConcurrent)
                UsageTile(title: "Start rate", value: self.startRate)
            }

            VStack(alignment: .leading, spacing: 6) {
                MiniUsageBars(values: self.usage?.concurrentSeries ?? [], color: .green)
                MiniUsageBars(values: self.usage?.startRateSeries ?? [], color: .orange)
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

    private var startsInWindow: String {
        guard let usage else { return "--" }
        return "\(usage.estimatedStartsInWindow)"
    }

    private var peakConcurrent: String {
        guard let usage else { return "--" }
        return "\(usage.peakConcurrent)"
    }

    private var startRate: String {
        guard let usage else { return "--" }
        return "\(Self.number(usage.latestStartsPerMinute))/min"
    }

    private var footerLine: String {
        if !self.hasTeamID {
            return "Add a team ID in Settings to load team metrics."
        }
        if let usageError, !usageError.isEmpty {
            return usageError
        }
        if self.usage == nil {
            return "Usage has not been loaded yet."
        }

        let cost = "Est. cost \(AppModel.currency(self.estimatedDailyCostUSD))"
        guard self.alertsEnabled else { return "\(cost) · alerts off" }

        var limits: [String] = []
        if self.concurrentLimit > 0 { limits.append("C \(self.concurrentLimit)") }
        if self.startsLimit > 0 { limits.append("starts \(self.startsLimit)") }
        if self.costLimitUSD > 0 { limits.append("cost \(AppModel.currency(self.costLimitUSD))") }
        if limits.isEmpty { return "\(cost) · no limits set" }
        return "\(cost) · alert limits: \(limits.joined(separator: ", "))"
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
                        .fill(Color.secondary.opacity(0.15))
                        .frame(height: 3)
                } else {
                    ForEach(Array(samples.enumerated()), id: \.offset) { _, value in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(self.color.opacity(0.62))
                            .frame(
                                width: barWidth,
                                height: max(3, proxy.size.height * CGFloat(value / maxValue))
                            )
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .frame(height: 26)
        .accessibilityHidden(true)
    }
}
