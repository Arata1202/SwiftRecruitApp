import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // Keep the explicit callbacks: returning from the async protocol bridge can
    // invoke UIKit's completion on a cooperative executor, even after MainActor.run.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completeForegroundNotification(completionHandler: completionHandler)
    }

    nonisolated func completeForegroundNotification(
        completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        DispatchQueue.main.async {
            completionHandler([.banner, .sound])
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        handleNotificationResponse(
            actionIdentifier: response.actionIdentifier,
            contentUserInfo: response.notification.request.content.userInfo,
            completionHandler: completionHandler
        )
    }

    // A value-input boundary also allows testing without constructing framework
    // notification responses, which have no public initializer.
    nonisolated func handleNotificationResponse(
        actionIdentifier: String,
        contentUserInfo: [AnyHashable: Any],
        completionHandler: @escaping () -> Void
    ) {
        // Extract only value data on the caller's queue; do not transfer the
        // notification/response or its arbitrary userInfo objects across queues.
        let userInfo = Self.eventUserInfo(actionIdentifier: actionIdentifier, contentUserInfo: contentUserInfo)
        DispatchQueue.main.async {
            // Ignored actions and malformed payloads must also finish on main.
            defer { completionHandler() }
            guard let userInfo else { return }
            PendingNotificationStore.save(userInfo: userInfo)
            NotificationCenter.default.post(
                name: .didReceiveRecruitNotification,
                object: nil,
                userInfo: userInfo
            )
        }
    }

    private nonisolated static func eventUserInfo(
        actionIdentifier: String,
        contentUserInfo: [AnyHashable: Any]
    ) -> [String: String]? {
        guard actionIdentifier == UNNotificationDefaultActionIdentifier,
              let kind = contentUserInfo["kind"] as? String,
              let itemID = contentUserInfo["item_id"] as? String
        else { return nil }

        var eventUserInfo = [
            "kind": kind,
            "item_id": itemID,
        ]
        if let companyID = contentUserInfo["company_id"] as? String {
            eventUserInfo["company_id"] = companyID
        }
        if let userID = contentUserInfo["user_id"] as? String {
            eventUserInfo["user_id"] = userID
        }
        return eventUserInfo
    }
}
