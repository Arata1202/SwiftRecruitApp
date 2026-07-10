import Foundation
import Observation
import Supabase

@MainActor
@Observable
final class AppContainer {
    let configuration: AppConfiguration
    let client: SupabaseClient?
    let session: AppSession
    let store: RecruitStore
    let router = AppRouter()
    let notifications: LocalNotificationService

    init(configuration: AppConfiguration = .current) {
        self.configuration = configuration
        let notificationService = LocalNotificationService()
        notifications = notificationService

        if configuration.isConfigured,
           let url = configuration.supabaseURL {
            let client = SupabaseClient(
                supabaseURL: url,
                supabaseKey: configuration.supabasePublishableKey
            )
            self.client = client
            session = AppSession(client: client)
            store = RecruitStore(repository: SupabaseRecruitRepository(client: client), notifications: notificationService)
        } else {
            client = nil
            session = AppSession(client: nil)
            store = RecruitStore(repository: nil, notifications: notificationService)
        }
    }
}
