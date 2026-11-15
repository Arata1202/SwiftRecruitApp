import XCTest
@testable import SwiftRecruitApp

@MainActor
final class AppleCalendarServiceTests: XCTestCase {
    func testManuallyAddedEventKeepsConfigurationVisibleWithoutAccess() async throws {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        _ = try await context.service.export(makeDescriptor(title: "面接"))
        context.client.hasFullAccess = false
        XCTAssertTrue(context.service.hasExistingCalendarConfiguration)
    }

    func testExportUpdatesExistingEventWithoutCreatingDuplicate() async throws {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let descriptor = makeDescriptor(title: "一次面接")

        let firstExportCreatedRecord = try await context.service.export(descriptor)
        let secondExportCreatedRecord = try await context.service.export(
            makeDescriptor(title: "最終面接")
        )

        XCTAssertTrue(firstExportCreatedRecord)
        XCTAssertFalse(secondExportCreatedRecord)
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

    func testAccountDeletionFindsManagedEventWithoutLocalRecord() async throws {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let descriptor = makeDescriptor(title: "面接")

        try await context.service.removeAllManagedEvents(matching: [descriptor])

        XCTAssertEqual(context.client.removeCalls.count, 1)
        XCTAssertNil(context.client.removeCalls[0].identifier)
        XCTAssertEqual(context.client.removeCalls[0].key, descriptor.key)
        XCTAssertEqual(context.client.removeCalls[0].lastStartDate, descriptor.startDate)
    }

    func testAccountDeletionRequiresAccessWhenLocalRecordsExist() async throws {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let descriptor = makeDescriptor(title: "面接")
        _ = try await context.service.export(descriptor)
        context.client.hasFullAccess = false

        do {
            try await context.service.removeAllManagedEvents(matching: [descriptor])
            XCTFail("管理済み予定がある場合はアクセス拒否を通知する必要があります")
        } catch AppleCalendarError.accessDenied {}

        XCTAssertTrue(context.service.isExported(key: descriptor.key))
    }

    func testAccessRequestIsCancelledWhenSessionChangesAndReturnsToSameUser() async {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let userID = UUID()
        context.service.activate(userID: userID)
        context.client.hasFullAccess = false
        context.client.suspendsAccessRequest = true

        let request = Task { try await context.service.ensureAutoSyncAccess() }
        await context.client.waitForAccessRequest()
        context.service.activate(userID: nil)
        context.service.activate(userID: userID)
        context.client.finishAccessRequest(granted: true)

        do {
            try await request.value
            XCTFail("セッション変更前の権限リクエストはキャンセルされる必要があります")
        } catch is CancellationError {
        } catch {
            XCTFail("予期しないエラー: \(error)")
        }
    }

    func testDeniedAccessAfterSessionChangeDoesNotReturnStaleError() async {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        context.client.hasFullAccess = false
        context.client.suspendsAccessRequest = true

        let request = Task { try await context.service.ensureAutoSyncAccess() }
        await context.client.waitForAccessRequest()
        context.service.activate(userID: UUID())
        context.client.finishAccessRequest(granted: false)

        do {
            try await request.value
            XCTFail("古いセッションの権限リクエストはキャンセルされる必要があります")
        } catch is CancellationError {
        } catch {
            XCTFail("古いセッションのエラーを返しました: \(error)")
        }
    }

    func testPurgingPreferencesRemovesDeletedUsersRecords() async throws {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let descriptor = makeDescriptor(title: "面接")
        let userID = UUID()
        context.service.activate(userID: userID)
        _ = try await context.service.export(descriptor)
        context.service.setCategory(.task, enabled: true)
        context.defaults.set(Data([0x01]), forKey: "appleCalendarExportRecords.v1")
        context.defaults.set(true, forKey: "appleCalendarUserScopeMigration.v2")

        context.service.purgePreferences(userID: userID)

        XCTAssertFalse(context.service.isExported(key: descriptor.key))
        XCTAssertFalse(context.service.isCategoryEnabled(.task))
        XCTAssertNil(context.defaults.object(forKey: "appleCalendarExportRecords.v1"))
        XCTAssertNil(context.defaults.object(forKey: "appleCalendarUserScopeMigration.v2"))
    }

    func testLegacyAutoSyncDoesNotRecreateExternallyDeletedEvent() async throws {
        let suiteName = "AppleCalendarServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "appleCalendarAutoSyncEnabled.v1")
        let client = MockAppleCalendarEventClient()
        let service = AppleCalendarService(defaults: defaults, client: client)
        service.activate(userID: UUID())
        let managed = makeDescriptor(title: "管理済み")
        let unregistered = AppleCalendarEventDescriptor(key: "unregistered", title: "未登録", notes: nil, startDate: managed.startDate, hasTime: true, duration: 3600)
        _ = try await service.export(managed)
        client.deleteExternally(identifier: "event-test")

        // Coordinator checks isExported before syncing each current event.
        for descriptor in [managed, unregistered] where service.isExported(key: descriptor.key) {
            try await service.sync(descriptor)
        }
        XCTAssertFalse(service.isExported(key: managed.key))
        XCTAssertFalse(service.isExported(key: unregistered.key))
        XCTAssertFalse(service.hasManagedEvents)
        XCTAssertEqual(client.saveCalls.count, 1)
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

    struct RemoveCall {
        let identifier: String?
        let lastStartDate: Date
        let key: String
    }

    var hasFullAccess = true
    var suspendsAccessRequest = false
    private var accessRequest: CheckedContinuation<Bool, Never>?
    private var accessRequestWaiter: CheckedContinuation<Void, Never>?
    var removeError: Error?
    var saveCalls: [SaveCall] = []
    var removeCalls: [RemoveCall] = []
    var removeCallCount: Int { removeCalls.count }
    private var identifiers: Set<String> = []

    func deleteExternally(identifier: String) { identifiers.remove(identifier) }

    func requestFullAccess() async throws -> Bool {
        if suspendsAccessRequest {
            let granted = await withCheckedContinuation { continuation in
                accessRequest = continuation
                accessRequestWaiter?.resume()
                accessRequestWaiter = nil
            }
            hasFullAccess = granted
            return granted
        }
        hasFullAccess = true
        return true
    }

    func waitForAccessRequest() async {
        if accessRequest != nil { return }
        await withCheckedContinuation { accessRequestWaiter = $0 }
    }

    func finishAccessRequest(granted: Bool) {
        accessRequest?.resume(returning: granted)
        accessRequest = nil
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

    func remove(identifier: String?, lastStartDate: Date, key: String) throws {
        removeCalls.append(
            RemoveCall(
                identifier: identifier,
                lastStartDate: lastStartDate,
                key: key
            )
        )
        if let removeError { throw removeError }
        if let identifier {
            identifiers.remove(identifier)
        }
    }
}

private enum TestError: Error {
    case failed
}
