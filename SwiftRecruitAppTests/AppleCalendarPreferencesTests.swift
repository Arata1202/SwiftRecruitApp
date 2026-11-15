import XCTest
@testable import SwiftRecruitApp

final class AppleCalendarPreferencesTests: XCTestCase {
    @MainActor
    func testExistingConfigurationDetectsExplicitOffAndIsUserScoped() async throws {
        let (defaults, suiteName) = Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = AppleCalendarService(defaults: defaults)
        let firstUser = UUID()
        service.activate(userID: firstUser)
        XCTAssertFalse(service.hasExistingCalendarConfiguration)

        defaults.set(false, forKey: "appleCalendarAutoSyncEnabled.v2.\(firstUser.uuidString)")
        XCTAssertTrue(service.hasExistingCalendarConfiguration)

        service.activate(userID: UUID())
        XCTAssertFalse(service.hasExistingCalendarConfiguration)
        service.activate(userID: firstUser)
        XCTAssertTrue(service.hasExistingCalendarConfiguration)
    }

    @MainActor
    func testExplicitlyDisabledCategoryIsExistingConfiguration() {
        let (defaults, suiteName) = Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = AppleCalendarService(defaults: defaults)
        service.activate(userID: UUID())
        service.setCategory(.task, enabled: false)
        XCTAssertTrue(service.hasExistingCalendarConfiguration)
    }

    @MainActor
    func testSelectionToggledBackOffRemainsExistingConfiguration() {
        let (defaults, suiteName) = Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = AppleCalendarService(defaults: defaults)
        service.activate(userID: UUID())
        service.setCategory(.selection, enabled: true)
        service.setCategory(.selection, enabled: false)
        XCTAssertTrue(service.hasExistingCalendarConfiguration)
    }

    @MainActor
    func testNoSyncCategoriesArePreselectedByDefault() {
        let (defaults, suiteName) = Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = AppleCalendarService(defaults: defaults)
        service.activate(userID: UUID())

        XCTAssertFalse(service.isCategoryEnabled(.selection))
        XCTAssertFalse(service.isCategoryEnabled(.deadline))
        XCTAssertFalse(service.isCategoryEnabled(.task))
    }

    @MainActor
    func testExistingEnabledAutoSyncPreservesPreviouslyImplicitSelection() {
        let (defaults, suiteName) = Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let userID = UUID()
        defaults.set(true, forKey: "appleCalendarAutoSyncEnabled.v2.\(userID.uuidString)")
        let service = AppleCalendarService(defaults: defaults)
        service.activate(userID: userID)

        XCTAssertTrue(service.isCategoryEnabled(.selection))
        XCTAssertFalse(service.isCategoryEnabled(.deadline))
        XCTAssertFalse(service.isCategoryEnabled(.task))
    }

    @MainActor
    func testExistingOtherCategoryPreservesImplicitSelectionEvenWhenSyncIsOff() {
        let (defaults, suiteName) = Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let userID = UUID()
        defaults.set(true, forKey: "appleCalendarAutoSyncCategory.v2.task.\(userID.uuidString)")
        let service = AppleCalendarService(defaults: defaults)
        service.activate(userID: userID)

        XCTAssertTrue(service.isCategoryEnabled(.selection))
        XCTAssertTrue(service.isCategoryEnabled(.task))
    }

    @MainActor
    func testLegacyEnabledAutoSyncPreservesImplicitSelection() {
        let (defaults, suiteName) = Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "appleCalendarAutoSyncEnabled.v1")
        let service = AppleCalendarService(defaults: defaults)
        service.activate(userID: UUID())

        XCTAssertTrue(service.isCategoryEnabled(.selection))
    }

    @MainActor
    func testExistingDisabledAutoSyncPreservesImplicitSelection() {
        let (defaults, suiteName) = Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let userID = UUID()
        defaults.set(false, forKey: "appleCalendarAutoSyncEnabled.v2.\(userID.uuidString)")
        let service = AppleCalendarService(defaults: defaults)
        service.activate(userID: userID)

        XCTAssertTrue(service.isCategoryEnabled(.selection))
    }

    @MainActor
    func testExplicitlyEnabledSelectionStaysEnabled() {
        let (defaults, suiteName) = Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let userID = UUID()
        defaults.set(true, forKey: "appleCalendarAutoSyncCategory.v2.selection.\(userID.uuidString)")
        let service = AppleCalendarService(defaults: defaults)
        service.activate(userID: userID)

        XCTAssertTrue(service.isCategoryEnabled(.selection))
    }

    @MainActor
    func testExplicitlyDisabledSelectionStaysDisabled() {
        let (defaults, suiteName) = Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let userID = UUID()
        defaults.set(false, forKey: "appleCalendarAutoSyncCategory.v2.selection.\(userID.uuidString)")
        defaults.set(true, forKey: "appleCalendarAutoSyncCategory.v2.task.\(userID.uuidString)")
        let service = AppleCalendarService(defaults: defaults)
        service.activate(userID: userID)

        XCTAssertFalse(service.isCategoryEnabled(.selection))
        XCTAssertTrue(service.isCategoryEnabled(.task))
        service.activate(userID: userID)
        XCTAssertFalse(service.isCategoryEnabled(.selection))
    }

    @MainActor
    func testCategoryPreferencesPersist() {
        let (defaults, suiteName) = Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = AppleCalendarService(defaults: defaults)
        let userID = UUID()
        service.activate(userID: userID)

        service.setCategory(.deadline, enabled: true)

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
