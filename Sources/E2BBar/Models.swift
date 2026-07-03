import Foundation

struct DashboardSnapshot: Sendable {
    var sandboxes: [E2BSandbox]
    var totals: E2BListTotals
    var refreshedAt: Date?
    var error: String?

    static let empty = DashboardSnapshot(
        sandboxes: [],
        totals: E2BListTotals(),
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
        DashboardSnapshot(sandboxes: sandboxes, totals: totals, refreshedAt: refreshedAt, error: error)
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
