import Foundation

struct AppConfiguration: Sendable {
    let supabaseURL: URL?
    let supabasePublishableKey: String

    var isConfigured: Bool {
        guard let supabaseURL, let scheme = supabaseURL.scheme?.lowercased(),
              ["https", "http"].contains(scheme), supabaseURL.host?.isEmpty == false else { return false }
        return supabaseURL.host?.contains("YOUR_PROJECT_REF") == false
            && supabasePublishableKey.isEmpty == false
            && supabasePublishableKey != "YOUR_PUBLISHABLE_KEY"
    }

    static let current = AppConfiguration(
        supabaseURL: Bundle.main.stringValue(forInfoKey: "SUPABASE_URL").flatMap(URL.init(string:)),
        supabasePublishableKey: Bundle.main.stringValue(forInfoKey: "SUPABASE_PUBLISHABLE_KEY") ?? ""
    )
}

private extension Bundle {
    func stringValue(forInfoKey key: String) -> String? {
        guard let value = object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

