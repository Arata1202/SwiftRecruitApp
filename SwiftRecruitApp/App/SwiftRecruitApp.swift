import SwiftUI

@main
struct SwiftRecruitApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(container)
                .environment(container.session)
                .environment(container.store)
                .environment(container.router)
                .tint(.accentColor)
        }
    }
}

