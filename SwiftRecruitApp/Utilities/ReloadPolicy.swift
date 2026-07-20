import Foundation

enum ReloadPolicy {
    static let defaultMinimumInterval: TimeInterval = 5 * 60

    static func shouldReload(
        lastSuccessfulReloadAt: Date?,
        now: Date = Date(),
        minimumInterval: TimeInterval = defaultMinimumInterval
    ) -> Bool {
        guard let lastSuccessfulReloadAt else { return true }
        return now.timeIntervalSince(lastSuccessfulReloadAt) >= minimumInterval
    }
}
