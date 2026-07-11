import SwiftUI

@main
struct SwiftRecruitApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var container = AppContainer()
    @AppStorage("appAppearance") private var appAppearance = AppAppearance.system.rawValue

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(container)
                .environment(container.session)
                .environment(container.store)
                .environment(container.router)
                .tint(.accentColor)
                .preferredColorScheme(AppAppearance(rawValue: appAppearance)?.colorScheme)
        }
    }
}
