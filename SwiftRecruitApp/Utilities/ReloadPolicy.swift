import Foundation

enum ReloadPolicy {
    static let defaultMinimumInterval: TimeInterval = 5 * 60

    static func shouldReload(
        lastSuccessfulReloadAt: Date?,
        now: Date = Date(),
        minimumInterval: TimeInterval = defaultMinimumInterval
    ) -> Bool {
        guard let lastSuccessfulReloadAt else { return true }
        let elapsed = now.timeIntervalSince(lastSuccessfulReloadAt)
        return elapsed < 0 || elapsed >= minimumInterval
    }
}
