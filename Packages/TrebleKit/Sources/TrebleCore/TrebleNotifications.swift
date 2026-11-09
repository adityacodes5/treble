import Foundation
import UserNotifications

/// Posts macOS notifications on behalf of features.
///
/// macOS asks the user for permission the first time a notification is
/// actually needed, never at launch.
@MainActor
public enum TrebleNotifications {
    private static let delegate = PresentingDelegate()

    public static func post(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.delegate = delegate

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)

        Task {
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            guard granted else { return }
            try? await center.add(request)
        }
    }
}

/// Shows banners even if a Treble window happens to be in front.
private final class PresentingDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
