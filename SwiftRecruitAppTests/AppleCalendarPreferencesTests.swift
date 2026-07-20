import XCTest
@testable import SwiftRecruitApp

final class AppleCalendarPreferencesTests: XCTestCase {
    @MainActor
    func testOnlySelectionSyncIsPreselectedByDefault() {
        let (defaults, suiteName) = Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = AppleCalendarService(defaults: defaults)

        XCTAssertTrue(service.isCategoryEnabled(.selection))
        XCTAssertFalse(service.isCategoryEnabled(.deadline))
        XCTAssertFalse(service.isCategoryEnabled(.task))
        XCTAssertFalse(service.isAutoSyncEnabled)
    }

    @MainActor
    func testCategoryPreferencesPersist() {
        let (defaults, suiteName) = Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = AppleCalendarService(defaults: defaults)

        service.setCategory(.deadline, enabled: true)
        service.setCategory(.selection, enabled: false)

        let restored = AppleCalendarService(defaults: defaults)
        XCTAssertTrue(restored.isCategoryEnabled(.deadline))
        XCTAssertFalse(restored.isCategoryEnabled(.selection))
    }

    private static func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "AppleCalendarPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}
