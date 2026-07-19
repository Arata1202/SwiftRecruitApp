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

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let contentUserInfo = response.notification.request.content.userInfo
        guard let kind = contentUserInfo["kind"] as? String,
              let itemID = contentUserInfo["item_id"] as? String
        else { return }

        var eventUserInfo = [
            "kind": kind,
            "item_id": itemID,
        ]
        if let companyID = contentUserInfo["company_id"] as? String {
            eventUserInfo["company_id"] = companyID
        }
        let userInfo = eventUserInfo

        await MainActor.run {
            PendingNotificationStore.save(userInfo: userInfo)
            NotificationCenter.default.post(
                name: .didReceiveRecruitNotification,
                object: nil,
                userInfo: userInfo
            )
        }
    }
}
