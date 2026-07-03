import AppKit
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshot = DashboardSnapshot.empty
    @Published var isRefreshing = false
    @Published private(set) var credentialState = CredentialState.missing
    @Published private(set) var lastActionMessage: String?
    @Published var stateFilter: SandboxStateFilter {
        didSet {
            defaults.set(stateFilter.rawValue, forKey: DefaultsKey.stateFilter)
            Task { await refresh() }
        }
    }
    @Published var metadataFilter: String {
        didSet { defaults.set(metadataFilter, forKey: DefaultsKey.metadataFilter) }
    }
    @Published var pollInterval: TimeInterval {
        didSet {
            defaults.set(pollInterval, forKey: DefaultsKey.pollInterval)
            onPollIntervalChange?(pollInterval)
        }
    }
    @Published var launchAtLoginEnabled: Bool {
        didSet {
            defaults.set(launchAtLoginEnabled, forKey: DefaultsKey.launchAtLoginEnabled)
            updateLaunchAtLogin(enabled: launchAtLoginEnabled)
        }
    }

    var onSnapshotChange: (() -> Void)?
    var onPollIntervalChange: ((TimeInterval) -> Void)?

    private let defaults = UserDefaults.standard
    private let keychain = Keychain(service: "com.hancengiz.e2bbar")
    private var cachedAPIKey: String?

    init() {
        let savedFilter = defaults.string(forKey: DefaultsKey.stateFilter)
        stateFilter = savedFilter.flatMap(SandboxStateFilter.init(rawValue:)) ?? .all
        metadataFilter = defaults.string(forKey: DefaultsKey.metadataFilter) ?? ""
        let interval = defaults.double(forKey: DefaultsKey.pollInterval)
        pollInterval = interval > 0 ? interval : 60
        if let savedLaunchAtLogin = defaults.object(forKey: DefaultsKey.launchAtLoginEnabled) as? Bool {
            launchAtLoginEnabled = savedLaunchAtLogin
        } else {
            launchAtLoginEnabled = LaunchAtLoginManager.isEnabled
            defaults.set(launchAtLoginEnabled, forKey: DefaultsKey.launchAtLoginEnabled)
        }
        updateLaunchAtLogin(enabled: launchAtLoginEnabled)
        reloadCredentialState()
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let apiKey = try currentAPIKey()
            let client = E2BClient(apiKey: apiKey)
            let result = try await client.listSandboxes(
                states: stateFilter.states,
                metadata: metadataFilter,
                limit: 100
            )
            let sortedSandboxes = result.sandboxes.sorted { lhs, rhs in
                switch (lhs.state, rhs.state) {
                case (.running, .paused): return true
                case (.paused, .running): return false
                default:
                    return (lhs.endAt ?? .distantFuture) < (rhs.endAt ?? .distantFuture)
                }
            }
            apply(DashboardSnapshot(
                sandboxes: sortedSandboxes,
                totals: result.totals,
                refreshedAt: Date(),
                error: nil
            ))
        } catch {
            apply(snapshot.with(error: Self.errorMessage(error)))
        }
    }

    func saveAPIKey(_ apiKey: String) {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard Self.isValidAPIKey(trimmed) else {
            apply(snapshot.with(error: AppError.invalidAPIKeyFormat.localizedDescription))
            return
        }
        do {
            try keychain.set(trimmed, account: KeychainAccount.apiKey)
            cachedAPIKey = trimmed
            reloadCredentialState()
            Task { await refresh() }
        } catch {
            apply(snapshot.with(error: Self.errorMessage(error)))
        }
    }

    func clearSavedAPIKey() {
        cachedAPIKey = nil
        do {
            try keychain.delete(account: KeychainAccount.apiKey)
            reloadCredentialState()
            apply(.empty.with(error: "Saved API key cleared"))
        } catch {
            apply(snapshot.with(error: Self.errorMessage(error)))
        }
    }

    func openDashboard() {
        open("https://e2b.dev/dashboard")
    }

    func openDocs() {
        open("https://e2b.dev/docs/sandbox/list")
    }

    func openWebsite() {
        open("https://e2b.bar")
    }

    func openGitHub() {
        open("https://github.com/fabriqaai/e2b-bar")
    }

    func openReleases() {
        open("https://github.com/fabriqaai/e2b-bar/releases")
    }

    func copySandboxID(_ sandboxID: String) {
        copyToPasteboard(sandboxID)
        setActionMessage("Copied sandbox ID \(shortID(sandboxID))")
    }

    func copySandboxLogs(_ sandboxID: String) async {
        do {
            let client = try currentClient()
            let logs = try await client.getSandboxLogs(sandboxID: sandboxID, limit: 200)
            copyToPasteboard(E2BLogEntry.transcript(sandboxID: sandboxID, logs: logs))
            setActionMessage("Copied \(logs.count) log entries for \(shortID(sandboxID))")
        } catch {
            apply(snapshot.with(error: Self.errorMessage(error)))
        }
    }

    func copySandboxMetrics(_ sandboxID: String) async {
        do {
            let client = try currentClient()
            let end = Int64(Date().timeIntervalSince1970)
            let start = end - 15 * 60
            let metrics = try await client.getSandboxMetrics(sandboxID: sandboxID, start: start, end: end)
            copyToPasteboard(E2BMetric.summary(sandboxID: sandboxID, metrics: metrics))
            setActionMessage("Copied metrics for \(shortID(sandboxID))")
        } catch {
            apply(snapshot.with(error: Self.errorMessage(error)))
        }
    }

    func refreshSandboxTTL(_ sandboxID: String, duration: Int) async {
        do {
            let client = try currentClient()
            try await client.refreshSandbox(sandboxID: sandboxID, duration: duration)
            setActionMessage("Extended \(shortID(sandboxID)) by \(Self.durationLabel(duration))")
            await refresh()
        } catch {
            apply(snapshot.with(error: Self.errorMessage(error)))
        }
    }

    func setSandboxTimeout(_ sandboxID: String, timeout: Int) async {
        do {
            let client = try currentClient()
            try await client.setSandboxTimeout(sandboxID: sandboxID, timeout: timeout)
            setActionMessage("Set \(shortID(sandboxID)) timeout to \(Self.durationLabel(timeout))")
            await refresh()
        } catch {
            apply(snapshot.with(error: Self.errorMessage(error)))
        }
    }

    func pauseSandbox(_ sandboxID: String) async {
        do {
            let client = try currentClient()
            try await client.pauseSandbox(sandboxID: sandboxID, memory: true)
            setActionMessage("Paused \(shortID(sandboxID))")
            await refresh()
        } catch {
            apply(snapshot.with(error: Self.errorMessage(error)))
        }
    }

    func deleteSandbox(_ sandboxID: String) async {
        do {
            let client = try currentClient()
            try await client.deleteSandbox(sandboxID: sandboxID)
            setActionMessage("Deleted \(shortID(sandboxID))")
            await refresh()
        } catch {
            apply(snapshot.with(error: Self.errorMessage(error)))
        }
    }

    private func currentAPIKey() throws -> String {
        if let cachedAPIKey, !cachedAPIKey.isEmpty {
            guard Self.isValidAPIKey(cachedAPIKey) else { throw AppError.invalidAPIKeyFormat }
            return cachedAPIKey
        }
        if let keychainKey = try keychain.get(account: KeychainAccount.apiKey), !keychainKey.isEmpty {
            guard Self.isValidAPIKey(keychainKey) else { throw AppError.invalidAPIKeyFormat }
            cachedAPIKey = keychainKey
            return keychainKey
        }
        if let environmentKey = ProcessInfo.processInfo.environment["E2B_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !environmentKey.isEmpty
        {
            guard Self.isValidAPIKey(environmentKey) else { throw AppError.invalidAPIKeyFormat }
            return environmentKey
        }
        throw AppError.missingAPIKey
    }

    private func currentClient() throws -> E2BClient {
        E2BClient(apiKey: try currentAPIKey())
    }

    private func reloadCredentialState() {
        do {
            if let key = try keychain.get(account: KeychainAccount.apiKey), !key.isEmpty {
                guard Self.isValidAPIKey(key) else {
                    credentialState = .error(AppError.invalidAPIKeyFormat.localizedDescription)
                    return
                }
                credentialState = .configured(source: "Keychain")
                return
            }
        } catch {
            credentialState = .error(Self.errorMessage(error))
            return
        }
        if let environmentKey = ProcessInfo.processInfo.environment["E2B_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !environmentKey.isEmpty
        {
            guard Self.isValidAPIKey(environmentKey) else {
                credentialState = .error(AppError.invalidAPIKeyFormat.localizedDescription)
                return
            }
            credentialState = .configured(source: "E2B_API_KEY")
        } else {
            credentialState = .missing
        }
    }

    private func apply(_ newSnapshot: DashboardSnapshot) {
        snapshot = newSnapshot
        onSnapshotChange?()
    }

    private func setActionMessage(_ message: String) {
        lastActionMessage = message
        onSnapshotChange?()
    }

    private func updateLaunchAtLogin(enabled: Bool) {
        do {
            try LaunchAtLoginManager.setEnabled(enabled)
        } catch {
            snapshot = snapshot.with(error: "Launch at login: \(Self.errorMessage(error))")
            onSnapshotChange?()
        }
    }

    private func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func shortID(_ value: String) -> String {
        guard value.count > 12 else { return value }
        return "\(value.prefix(6))...\(value.suffix(4))"
    }

    private static func durationLabel(_ seconds: Int) -> String {
        if seconds % 3600 == 0 {
            return "\(seconds / 3600)h"
        }
        if seconds % 60 == 0 {
            return "\(seconds / 60)m"
        }
        return "\(seconds)s"
    }

    private static func errorMessage(_ error: Error) -> String {
        if let decodingError = error as? DecodingError {
            switch decodingError {
            case .keyNotFound(let key, _):
                return "Missing API field: \(key.stringValue)"
            case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
                return context.debugDescription
            @unknown default:
                return decodingError.localizedDescription
            }
        }
        return error.localizedDescription
    }

    private static func isValidAPIKey(_ value: String) -> Bool {
        guard value.hasPrefix("e2b_") else { return false }
        let suffix = value.dropFirst(4)
        guard !suffix.isEmpty else { return false }
        return suffix.allSatisfy { character in
            character.isHexDigit
        }
    }
}

enum SandboxStateFilter: String, CaseIterable, Hashable {
    case all
    case running
    case paused

    var label: String {
        switch self {
        case .all: "Running and paused"
        case .running: "Running"
        case .paused: "Paused"
        }
    }

    var states: [E2BSandboxState] {
        switch self {
        case .all: [.running, .paused]
        case .running: [.running]
        case .paused: [.paused]
        }
    }
}

enum CredentialState: Equatable {
    case missing
    case configured(source: String)
    case error(String)

    var label: String {
        switch self {
        case .missing:
            "No API key"
        case .configured(let source):
            "Configured from \(source)"
        case .error(let message):
            "Credential error: \(message)"
        }
    }
}

enum AppError: LocalizedError {
    case missingAPIKey
    case invalidAPIKeyFormat

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Add an E2B API key in Settings or launch with E2B_API_KEY"
        case .invalidAPIKeyFormat:
            "Invalid E2B API key format. Paste the secret key from the E2B dashboard; it should start with e2b_ followed by hex characters."
        }
    }
}

enum DefaultsKey {
    static let stateFilter = "stateFilter"
    static let metadataFilter = "metadataFilter"
    static let pollInterval = "pollInterval"
    static let launchAtLoginEnabled = "launchAtLoginEnabled"
}

enum KeychainAccount {
    static let apiKey = "e2b-api-key"
}
