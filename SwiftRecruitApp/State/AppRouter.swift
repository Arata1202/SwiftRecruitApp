import Foundation
import Observation

enum AppTab: Hashable {
    case home
    case companies
    case tasks
}

@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab = .home
    var companyPath: [UUID] = []
    var pendingTaskID: UUID?

    func openCompany(id: UUID) {
        selectedTab = .companies
        companyPath = [id]
    }

    func openTask(id: UUID) {
        selectedTab = .tasks
        pendingTaskID = id
    }
}

extension Notification.Name {
    static let didReceiveRecruitNotification = Notification.Name("didReceiveRecruitNotification")
}

