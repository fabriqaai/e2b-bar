import Foundation
import UserNotifications

enum UsageNotifier {
    static func notifyLimitCrossed(
        metricName: String,
        valueDescription: String,
        limitDescription: String,
        level: UsageAlertLevel
    ) async throws {
        guard try await ExpirationNotifier.requestAuthorization() else { return }

        let content = UNMutableNotificationContent()
        content.title = "E2B usage alert"
        content.body = "\(metricName) reached \(level.label): \(valueDescription) of \(limitDescription)."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "e2bbar-usage-\(metricName)-\(level.rawValue)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try await UNUserNotificationCenter.current().add(request)
    }
}
