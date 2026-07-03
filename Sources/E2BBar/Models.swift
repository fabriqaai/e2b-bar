import Foundation

struct DashboardSnapshot: Sendable {
    var sandboxes: [E2BSandbox]
    var totals: E2BListTotals
    var metrics: [String: SandboxMetricSummary]
    var refreshedAt: Date?
    var error: String?

    static let empty = DashboardSnapshot(
        sandboxes: [],
        totals: E2BListTotals(),
        metrics: [:],
        refreshedAt: nil,
        error: nil
    )

    var runningCount: Int {
        sandboxes.filter { $0.state == .running }.count
    }

    var pausedCount: Int {
        sandboxes.filter { $0.state == .paused }.count
    }

    var totalCPU: Int {
        sandboxes.reduce(0) { $0 + $1.cpuCount }
    }

    var totalMemoryMB: Int {
        sandboxes.reduce(0) { $0 + $1.memoryMB }
    }

    var nextExpiration: Date? {
        sandboxes.compactMap(\.endAt).filter { $0 > Date() }.min()
    }

    var isHealthy: Bool {
        error == nil
    }

    func with(error: String?) -> DashboardSnapshot {
        DashboardSnapshot(sandboxes: sandboxes, totals: totals, metrics: metrics, refreshedAt: refreshedAt, error: error)
    }
}

struct E2BListTotals: Hashable, Sendable {
    var fetched: Int = 0
    var runningHeader: Int?
    var pausedHeader: Int?

    var debugSummary: String {
        var parts = ["fetched \(fetched)"]
        if let runningHeader {
            parts.append("running \(runningHeader)")
        }
        if let pausedHeader {
            parts.append("paused \(pausedHeader)")
        }
        return parts.joined(separator: ", ")
    }
}

enum E2BSandboxState: String, Codable, Hashable, CaseIterable, Sendable {
    case running
    case paused
    case unknown

    var label: String {
        switch self {
        case .running: "running"
        case .paused: "paused"
        case .unknown: "unknown"
        }
    }
}

struct E2BSandbox: Decodable, Identifiable, Hashable, Sendable {
    var templateID: String
    var sandboxID: String
    var clientID: String?
    var startedAt: Date?
    var endAt: Date?
    var cpuCount: Int
    var memoryMB: Int
    var diskSizeMB: Int
    var state: E2BSandboxState
    var envdVersion: String?
    var alias: String?
    var metadata: [String: JSONValue]
    var volumeMounts: [VolumeMount]

    var id: String { sandboxID }

    var displayName: String {
        if let name = metadata.string(forKey: "name"), !name.isEmpty {
            return name
        }
        if let alias, !alias.isEmpty {
            return alias
        }
        if !templateID.isEmpty {
            return short(templateID)
        }
        return short(sandboxID)
    }

    var subtitle: String {
        let template = alias?.isEmpty == false ? alias! : short(templateID)
        return "\(state.label) - \(template)"
    }

    var resourceSummary: String {
        "\(cpuCount)c / \(Self.megabytes(memoryMB)) RAM / \(Self.megabytes(diskSizeMB)) disk"
    }

    var metadataSummary: String? {
        let pairs = metadata
            .sorted { $0.key < $1.key }
            .prefix(3)
            .map { "\($0.key)=\($0.value.shortDescription)" }
        guard !pairs.isEmpty else { return nil }
        return pairs.joined(separator: " ")
    }

    func short(_ value: String) -> String {
        guard value.count > 12 else { return value }
        return "\(value.prefix(6))...\(value.suffix(4))"
    }

    private static func megabytes(_ value: Int) -> String {
        guard value >= 1024 else { return "\(value)MB" }
        let gb = Double(value) / 1024.0
        if gb.rounded() == gb {
            return "\(Int(gb))GB"
        }
        return String(format: "%.1fGB", gb)
    }

    enum CodingKeys: String, CodingKey {
        case templateID
        case templateId
        case sandboxID
        case sandboxId
        case clientID
        case clientId
        case startedAt
        case endAt
        case cpuCount
        case memoryMB
        case diskSizeMB
        case state
        case envdVersion
        case alias
        case metadata
        case volumeMounts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.templateID = try container.decodeFlexibleString(keys: [.templateID, .templateId]) ?? ""
        self.sandboxID = try container.decodeFlexibleString(keys: [.sandboxID, .sandboxId]) ?? ""
        self.clientID = try container.decodeFlexibleString(keys: [.clientID, .clientId])
        self.startedAt = try container.decodeDateIfPresent(forKey: .startedAt)
        self.endAt = try container.decodeDateIfPresent(forKey: .endAt)
        self.cpuCount = try container.decodeIfPresent(Int.self, forKey: .cpuCount) ?? 0
        self.memoryMB = try container.decodeIfPresent(Int.self, forKey: .memoryMB) ?? 0
        self.diskSizeMB = try container.decodeIfPresent(Int.self, forKey: .diskSizeMB) ?? 0
        let rawState = try container.decodeIfPresent(String.self, forKey: .state)?.lowercased()
        self.state = rawState.flatMap(E2BSandboxState.init(rawValue:)) ?? .unknown
        self.envdVersion = try container.decodeFlexibleString(keys: [.envdVersion])
        self.alias = try container.decodeFlexibleString(keys: [.alias])
        self.metadata = try container.decodeIfPresent([String: JSONValue].self, forKey: .metadata) ?? [:]
        self.volumeMounts = try container.decodeIfPresent([VolumeMount].self, forKey: .volumeMounts) ?? []
    }
}

struct VolumeMount: Codable, Hashable, Sendable {
    var name: String
    var path: String
}

struct E2BMetric: Decodable, Hashable, Sendable {
    var timestamp: Date?
    var timestampUnix: Int64
    var cpuCount: Int
    var cpuUsedPct: Double
    var memUsed: Int64
    var memTotal: Int64
    var memCache: Int64
    var diskUsed: Int64
    var diskTotal: Int64

    enum CodingKeys: String, CodingKey {
        case timestamp
        case timestampUnix
        case cpuCount
        case cpuUsedPct
        case memUsed
        case memTotal
        case memCache
        case diskUsed
        case diskTotal
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let rawTimestamp = try container.decodeIfPresent(String.self, forKey: .timestamp) {
            self.timestamp = DateParsing.parse(rawTimestamp)
        } else {
            self.timestamp = nil
        }
        self.timestampUnix = try container.decodeIfPresent(Int64.self, forKey: .timestampUnix) ?? 0
        self.cpuCount = try container.decodeIfPresent(Int.self, forKey: .cpuCount) ?? 0
        self.cpuUsedPct = try container.decodeIfPresent(Double.self, forKey: .cpuUsedPct) ?? 0
        self.memUsed = try container.decodeIfPresent(Int64.self, forKey: .memUsed) ?? 0
        self.memTotal = try container.decodeIfPresent(Int64.self, forKey: .memTotal) ?? 0
        self.memCache = try container.decodeIfPresent(Int64.self, forKey: .memCache) ?? 0
        self.diskUsed = try container.decodeIfPresent(Int64.self, forKey: .diskUsed) ?? 0
        self.diskTotal = try container.decodeIfPresent(Int64.self, forKey: .diskTotal) ?? 0
    }

    static func summary(sandboxID: String, metrics: [E2BMetric]) -> String {
        guard !metrics.isEmpty else {
            return "E2BBar metrics for \(sandboxID)\n\nNo metrics returned for the selected interval."
        }

        let sorted = metrics.sorted { $0.timestampUnix < $1.timestampUnix }
        let latest = sorted.last!
        let avgCPU = sorted.map(\.cpuUsedPct).average
        let maxCPU = sorted.map(\.cpuUsedPct).max() ?? 0
        let memPercent = latest.memTotal > 0 ? Double(latest.memUsed) / Double(latest.memTotal) * 100 : 0
        let diskPercent = latest.diskTotal > 0 ? Double(latest.diskUsed) / Double(latest.diskTotal) * 100 : 0
        let range = Self.rangeDescription(sorted)

        return """
        E2BBar metrics for \(sandboxID)

        Samples: \(sorted.count)
        Window: \(range)
        CPU: avg \(Self.percent(avgCPU)), max \(Self.percent(maxCPU)), cores \(latest.cpuCount)
        Memory: \(Self.bytes(latest.memUsed)) / \(Self.bytes(latest.memTotal)) (\(Self.percent(memPercent)))
        Disk: \(Self.bytes(latest.diskUsed)) / \(Self.bytes(latest.diskTotal)) (\(Self.percent(diskPercent)))
        """
    }

    private static func rangeDescription(_ metrics: [E2BMetric]) -> String {
        guard let first = metrics.first, let last = metrics.last else { return "unknown" }
        let firstDate = first.timestamp ?? Date(timeIntervalSince1970: TimeInterval(first.timestampUnix))
        let lastDate = last.timestamp ?? Date(timeIntervalSince1970: TimeInterval(last.timestampUnix))
        return "\(firstDate.formatted(date: .omitted, time: .standard)) - \(lastDate.formatted(date: .omitted, time: .standard))"
    }

    private static func percent(_ value: Double) -> String {
        String(format: "%.1f%%", value)
    }

    private static func bytes(_ value: Int64) -> String {
        MetricFormatting.bytes(value)
    }
}

struct SandboxMetricSummary: Hashable, Sendable {
    var sampledAt: Date?
    var cpuUsedPercent: Double?
    var memoryUsedBytes: Int64?
    var memoryTotalBytes: Int64?
    var diskUsedBytes: Int64?
    var diskTotalBytes: Int64?

    init(metrics: [E2BMetric]) {
        let sorted = metrics.sorted { $0.timestampUnix < $1.timestampUnix }
        guard let latest = sorted.last else {
            self.sampledAt = nil
            self.cpuUsedPercent = nil
            self.memoryUsedBytes = nil
            self.memoryTotalBytes = nil
            self.diskUsedBytes = nil
            self.diskTotalBytes = nil
            return
        }
        self.sampledAt = latest.timestamp ?? Date(timeIntervalSince1970: TimeInterval(latest.timestampUnix))
        self.cpuUsedPercent = latest.cpuUsedPct
        self.memoryUsedBytes = latest.memUsed
        self.memoryTotalBytes = latest.memTotal
        self.diskUsedBytes = latest.diskUsed
        self.diskTotalBytes = latest.diskTotal
    }

    var cpuBadgeValue: String? {
        guard let cpuUsedPercent else { return nil }
        return MetricFormatting.percent(cpuUsedPercent, fractionDigits: 0)
    }

    var memoryBadgeValue: String? {
        guard let memoryUsedBytes, let memoryTotalBytes, memoryTotalBytes > 0 else { return nil }
        return "\(MetricFormatting.bytes(memoryUsedBytes))/\(MetricFormatting.bytes(memoryTotalBytes))"
    }

    var diskBadgeValue: String? {
        guard let diskUsedBytes, let diskTotalBytes, diskTotalBytes > 0 else { return nil }
        return "\(MetricFormatting.bytes(diskUsedBytes))/\(MetricFormatting.bytes(diskTotalBytes))"
    }
}

enum MetricFormatting {
    static func percent(_ value: Double, fractionDigits: Int = 1) -> String {
        String(format: "%.\(fractionDigits)f%%", value)
    }

    static func bytes(_ value: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var amount = Double(value)
        var unitIndex = 0
        while amount >= 1024, unitIndex < units.count - 1 {
            amount /= 1024
            unitIndex += 1
        }
        if unitIndex == 0 {
            return "\(Int(amount))\(units[unitIndex])"
        }
        return String(format: "%.1f%@", amount, units[unitIndex])
    }
}

struct E2BLogResponse: Decodable, Sendable {
    var logs: [E2BLogEntry]
}

struct E2BLogEntry: Decodable, Hashable, Sendable {
    var fields: [String: JSONValue]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.fields = try container.decode([String: JSONValue].self)
    }

    var timestampDescription: String? {
        self.stringValue(keys: ["timestamp", "time", "createdAt", "ts"])
    }

    var levelDescription: String? {
        self.stringValue(keys: ["level", "severity", "type"])
    }

    var messageDescription: String {
        if let message = self.stringValue(keys: ["message", "msg", "line", "text"]) {
            return message
        }
        return self.fields
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.shortDescription)" }
            .joined(separator: " ")
    }

    static func transcript(sandboxID: String, logs: [E2BLogEntry]) -> String {
        guard !logs.isEmpty else {
            return "E2BBar logs for \(sandboxID)\n\nNo logs returned."
        }

        let lines = logs.map { entry in
            [
                entry.timestampDescription,
                entry.levelDescription,
                entry.messageDescription
            ]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " ")
        }

        return "E2BBar logs for \(sandboxID)\n\n" + lines.joined(separator: "\n")
    }

    private func stringValue(keys: [String]) -> String? {
        for key in keys {
            guard let value = self.fields[key] else { continue }
            switch value {
            case .string(let string):
                return string
            default:
                return value.shortDescription
            }
        }
        return nil
    }
}

enum E2BLogDirection: String, Sendable {
    case forward
    case backward
}

enum JSONValue: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    var shortDescription: String {
        switch self {
        case .string(let value):
            value
        case .number(let value):
            if value.rounded() == value {
                "\(Int(value))"
            } else {
                String(format: "%.2f", value)
            }
        case .bool(let value):
            value ? "true" : "false"
        case .object(let value):
            "{\(value.count)}"
        case .array(let value):
            "[\(value.count)]"
        case .null:
            "null"
        }
    }
}

private extension Array where Element == Double {
    var average: Double {
        guard !self.isEmpty else { return 0 }
        return self.reduce(0, +) / Double(self.count)
    }
}

extension Dictionary where Key == String, Value == JSONValue {
    func string(forKey key: String) -> String? {
        guard case .string(let value)? = self[key] else { return nil }
        return value
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleString(keys: [Key]) throws -> String? {
        for key in keys {
            if let value = try decodeIfPresent(String.self, forKey: key) {
                return value
            }
        }
        return nil
    }

    func decodeDateIfPresent(forKey key: Key) throws -> Date? {
        guard let value = try decodeIfPresent(String.self, forKey: key), !value.isEmpty else { return nil }
        return DateParsing.parse(value)
    }
}

enum DateParsing {
    static func parse(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }
}
