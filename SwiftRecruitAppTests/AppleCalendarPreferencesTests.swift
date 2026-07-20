import XCTest
@testable import SwiftRecruitApp

final class AppleCalendarPreferencesTests: XCTestCase {
    @MainActor
    func testOnlySelectionSyncIsPreselectedByDefault() {
        let (defaults, suiteName) = Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = AppleCalendarService(defaults: defaults)
        service.activate(userID: UUID())

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
        let userID = UUID()
        service.activate(userID: userID)

        service.setCategory(.deadline, enabled: true)
        service.setCategory(.selection, enabled: false)

        let restored = AppleCalendarService(defaults: defaults)
        restored.activate(userID: userID)
        XCTAssertTrue(restored.isCategoryEnabled(.deadline))
        XCTAssertFalse(restored.isCategoryEnabled(.selection))
    }

    @MainActor
    func testPreferencesAreSeparatedByUser() {
        let (defaults, suiteName) = Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = AppleCalendarService(defaults: defaults)
        let firstUserID = UUID()
        let secondUserID = UUID()

        service.activate(userID: firstUserID)
        service.setCategory(.task, enabled: true)
        service.activate(userID: secondUserID)

        XCTAssertFalse(service.isCategoryEnabled(.task))
        service.activate(userID: firstUserID)
        XCTAssertTrue(service.isCategoryEnabled(.task))
    }

    private static func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "AppleCalendarPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}
