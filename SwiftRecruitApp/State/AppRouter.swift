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
    }
}

extension Notification.Name {
    static let didReceiveRecruitNotification = Notification.Name("didReceiveRecruitNotification")
}
