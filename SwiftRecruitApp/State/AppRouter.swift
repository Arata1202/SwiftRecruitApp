import Foundation
import Observation

enum AppTab: Hashable {
    case home
    case calendar
    case companies
    case tasks
}

@MainActor
@Observable
final class AppRouter {
    var notificationRoute = NotificationRouteState()
    var selectedTab: AppTab = .home
    var companyPath: [UUID] = []

    func openCompany(id: UUID) {
        selectedTab = .companies
        companyPath = [id]
    }

    func openTasks() {
        selectedTab = .tasks
    }

    func reset() {
        selectedTab = .home
        companyPath = []
        notificationRoute.reset()
        PendingNotificationStore.clear()
    }
}

extension Notification.Name {
    static let didReceiveRecruitNotification = Notification.Name("didReceiveRecruitNotification")
}
