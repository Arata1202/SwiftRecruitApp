import SwiftUI

struct MainTabView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.selectedTab) {
            HomeView()
                .tabItem { Label("ホーム", systemImage: "house") }
                .tag(AppTab.home)

            RecruitCalendarView()
                .tabItem { Label("カレンダー", systemImage: "calendar") }
                .tag(AppTab.calendar)

            CompaniesView()
                .tabItem { Label("企業", systemImage: "building.2") }
                .tag(AppTab.companies)

            TasksView()
                .tabItem { Label("ToDo", systemImage: "checklist") }
                .tag(AppTab.tasks)

        }
        .onReceive(NotificationCenter.default.publisher(for: .didReceiveRecruitNotification)) { notification in
            PendingNotificationStore.clear()
            handleNotification(notification.userInfo)
        }
        .onAppear {
            if let userInfo = PendingNotificationStore.take() {
                handleNotification(userInfo)
            }
        }
    }

    private func handleNotification(_ userInfo: [AnyHashable: Any]?) {
        guard let userInfo,
              let kind = userInfo["kind"] as? String,
              let itemValue = userInfo["item_id"] as? String,
              UUID(uuidString: itemValue) != nil
        else { return }

        if kind == "task" {
            router.openTasks()
        } else if kind == "selection",
                  let companyValue = userInfo["company_id"] as? String,
                  let companyID = UUID(uuidString: companyValue) {
            router.openCompany(id: companyID)
        }
    }
}
