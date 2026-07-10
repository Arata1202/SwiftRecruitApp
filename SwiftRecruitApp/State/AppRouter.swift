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
    var pendingSelectionID: UUID?
    var pendingTaskID: UUID?

    func openCompany(id: UUID) {
        selectedTab = .companies
        companyPath = [id]
    }

    func openTask(id: UUID) {
        selectedTab = .tasks
        pendingTaskID = id
    }

    func openSelection(id: UUID, companyID: UUID) {
        selectedTab = .companies
        companyPath = [companyID]
        pendingSelectionID = id
    }

    func reset() {
        selectedTab = .home
        companyPath = []
        pendingSelectionID = nil
        pendingTaskID = nil
    }
}

extension Notification.Name {
    static let didReceiveRecruitNotification = Notification.Name("didReceiveRecruitNotification")
}
