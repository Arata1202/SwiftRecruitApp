import XCTest
@testable import SwiftRecruitApp

@MainActor
final class AppleCalendarServiceTests: XCTestCase {
    func testExportUpdatesExistingEventWithoutCreatingDuplicate() async throws {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let descriptor = makeDescriptor(title: "一次面接")

        XCTAssertTrue(try await context.service.export(descriptor))
        XCTAssertFalse(try await context.service.export(makeDescriptor(title: "最終面接")))

        XCTAssertEqual(context.client.saveCalls.count, 2)
        XCTAssertNil(context.client.saveCalls[0].existingIdentifier)
        XCTAssertEqual(context.client.saveCalls[1].existingIdentifier, "event-test")
        XCTAssertEqual(context.client.saveCalls[1].descriptor.title, "最終面接")
    }

    func testFailedRemovalIsRetriedAndClearsManagedEvent() async throws {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let descriptor = makeDescriptor(title: "面接")
        _ = try await context.service.export(descriptor)
        context.client.removeError = TestError.failed

        do {
            try await context.service.remove(key: descriptor.key)
            XCTFail("削除は失敗する必要があります")
        } catch TestError.failed {}

        context.client.removeError = nil
        try await context.service.retryPendingRemovals()

        XCTAssertEqual(context.client.removeCallCount, 2)
        XCTAssertFalse(context.service.isExported(key: descriptor.key))
    }

    private func makeContext() -> (
        service: AppleCalendarService,
        client: MockAppleCalendarEventClient,
        defaults: UserDefaults,
        suiteName: String
    ) {
        let suiteName = "AppleCalendarServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let client = MockAppleCalendarEventClient()
        let service = AppleCalendarService(defaults: defaults, client: client)
        service.activate(userID: UUID())
        return (service, client, defaults, suiteName)
    }

    private func makeDescriptor(title: String) -> AppleCalendarEventDescriptor {
        AppleCalendarEventDescriptor(
            key: "test",
            title: title,
            notes: nil,
            startDate: Date(timeIntervalSince1970: 2_000_000_000),
            hasTime: true,
            duration: 3_600
        )
    }
}

@MainActor
private final class MockAppleCalendarEventClient: AppleCalendarEventClient {
    struct SaveCall {
        let descriptor: AppleCalendarEventDescriptor
        let existingIdentifier: String?
    }

    var hasFullAccess = true
    var removeError: Error?
    var saveCalls: [SaveCall] = []
    var removeCallCount = 0
    private var identifiers: Set<String> = []

    func requestFullAccess() async throws -> Bool {
        hasFullAccess = true
        return true
    }

    func contains(identifier: String, lastStartDate: Date, key: String) -> Bool {
        identifiers.contains(identifier)
    }

    func save(
        _ descriptor: AppleCalendarEventDescriptor,
        existingIdentifier: String?,
        lastStartDate: Date?
    ) throws -> AppleCalendarSavedEvent {
        saveCalls.append(SaveCall(descriptor: descriptor, existingIdentifier: existingIdentifier))
        let identifier = existingIdentifier ?? "event-\(descriptor.key)"
        identifiers.insert(identifier)
        return AppleCalendarSavedEvent(identifier: identifier, startDate: descriptor.startDate)
    }

    func remove(identifier: String, lastStartDate: Date, key: String) throws {
        removeCallCount += 1
        if let removeError { throw removeError }
        identifiers.remove(identifier)
    }
}

private enum TestError: Error {
    case failed
}
