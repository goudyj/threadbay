import Foundation
import UserNotifications

/// Posts macOS notifications for agent events; a click focuses the app and
/// selects the emitting session. Inert when running outside an app bundle
/// (`swift run`), where UserNotifications cannot be used.
@MainActor
final class NotificationService: NSObject {
    /// Installed by AppState; called with the session id of a clicked notification.
    var onSelectSession: ((UUID) -> Void)?

    private var available: Bool { Bundle.main.bundleIdentifier != nil }

    /// Registers as delegate and asks for authorization (once, system-managed).
    func setup() {
        guard available else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(title: String, body: String, sessionID: UUID) {
        guard available else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        if !body.isEmpty { content.body = body }
        content.userInfo = ["session_id": sessionID.uuidString]
        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    /// Shows banners even while the app is frontmost (terminal in view ≠ seen).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let raw = response.notification.request.content.userInfo["session_id"] as? String
        if let raw, let id = UUID(uuidString: raw) {
            Task { @MainActor in
                self.onSelectSession?(id)
            }
        }
        completionHandler()
    }
}
