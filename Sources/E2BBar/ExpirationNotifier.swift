import Foundation
import UserNotifications

enum ExpirationNotifier {
    static func requestAuthorization() async throws -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return try await center.requestAuthorization(options: [.alert, .sound])
        @unknown default:
            return false
        }
    }

    static func notifySandboxExpiring(
        sandbox: E2BSandbox,
        remaining: TimeInterval,
        threshold: ExpirationAlertThreshold
    ) async throws {
        guard try await Self.requestAuthorization() else { return }

        let content = UNMutableNotificationContent()
        content.title = "E2B sandbox expires soon"
        content.body = "\(sandbox.displayName) expires in \(Self.remainingLabel(remaining))."
        content.sound = .default
        content.userInfo = [
            "sandboxID": sandbox.sandboxID,
            "threshold": threshold.rawValue
        ]

        let request = UNNotificationRequest(
            identifier: "e2bbar-expiring-\(sandbox.sandboxID)-\(Int(sandbox.endAt?.timeIntervalSince1970 ?? 0))",
            content: content,
            trigger: nil
        )
        try await UNUserNotificationCenter.current().add(request)
    }

    private static func remainingLabel(_ remaining: TimeInterval) -> String {
        let minutes = max(1, Int((remaining / 60).rounded()))
        return minutes == 1 ? "1 minute" : "\(minutes) minutes"
    }
}

enum ExpirationAlertThreshold: Int, CaseIterable, Hashable {
    case off = 0
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case thirtyMinutes = 1800

    var label: String {
        switch self {
        case .off:
            "Off"
        case .fiveMinutes:
            "5 minutes"
        case .fifteenMinutes:
            "15 minutes"
        case .thirtyMinutes:
            "30 minutes"
        }
    }

    var seconds: Int? {
        self == .off ? nil : rawValue
    }
}
