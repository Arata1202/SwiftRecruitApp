import XCTest
import UIKit
@testable import SwiftRecruitApp

final class NotificationRouteStateTests: XCTestCase {
    private let userID = UUID()

    private func target(_ kind: String = "task", owner: UUID? = nil) -> NotificationTarget {
        var info = ["kind": kind, "item_id": UUID().uuidString]
        if let owner { info["user_id"] = owner.uuidString }
        return NotificationTarget(userInfo: info)!
    }

    func testColdTapWaitsForLoginAndWarmTapOpensSameDetail() {
        for cold in [true, false] {
            var state = NotificationRouteState()
            let item = target(owner: userID)
            state.enqueue(item, currentUserID: cold ? nil : userID)
            if cold {
                XCTAssertNil(state.begin(userID: nil, blocked: false))
                XCTAssertEqual(state.pending, item)
            }
            let request = state.begin(userID: userID, blocked: false)!
            XCTAssertEqual(request.target, item)
            XCTAssertEqual(state.phase, .loading)
            state.finish(request, currentUserID: userID, succeeded: true, exists: true)
            XCTAssertEqual(state.phase, .ready)
        }
    }

    func testAbsentRequiresSuccessfulReloadAndFailureCanRetry() {
        var state = NotificationRouteState()
        state.enqueue(target(), currentUserID: userID)
        let request = state.begin(userID: userID, blocked: false)!
        state.finish(request, currentUserID: userID, succeeded: false, exists: false)
        XCTAssertEqual(state.phase, .failed)
        state.retry()
        XCTAssertEqual(state.phase, .loading)
        state.finish(request, currentUserID: userID, succeeded: true, exists: false)
        XCTAssertEqual(state.phase, .missing)
    }

    func testRetainedDataDoesNotTurnFailedReloadIntoReady() {
        var state = NotificationRouteState()
        state.enqueue(target(), currentUserID: userID)
        let request = state.begin(userID: userID, blocked: false)!
        state.finish(request, currentUserID: userID, succeeded: false, exists: true)
        XCTAssertEqual(state.phase, .failed)
        state.retry()
        state.finish(request, currentUserID: userID, succeeded: true, exists: true)
        XCTAssertEqual(state.phase, .ready)
    }

    func testSheetDefersAndLatestDistinctTapQueuesWithoutReplacingActiveDraft() {
        var state = NotificationRouteState()
        let first = target()
        state.enqueue(first, currentUserID: userID)
        XCTAssertNil(state.begin(userID: userID, blocked: true))
        XCTAssertEqual(state.pending, first)
        let active = state.begin(userID: userID, blocked: false)!
        state.enqueue(first, currentUserID: userID)
        XCTAssertNil(state.pending)
        state.enqueue(target("selection"), currentUserID: userID)
        let latest = target("selection")
        state.enqueue(latest, currentUserID: userID)
        XCTAssertNil(state.begin(userID: userID, blocked: false))
        XCTAssertEqual(state.active, active)
        state.dismiss()
        XCTAssertNil(state.begin(userID: userID, blocked: true))
        XCTAssertEqual(state.begin(userID: userID, blocked: false)?.target, latest)
    }

    func testLogoutClearsQueueAndLateCompletionCannotOpenOldTarget() {
        var state = NotificationRouteState()
        state.enqueue(target(), currentUserID: userID)
        let old = state.begin(userID: userID, blocked: false)!
        state.enqueue(target(), currentUserID: userID)
        state.reset()
        state.finish(old, currentUserID: userID, succeeded: true, exists: true)
        XCTAssertNil(state.active)
        XCTAssertNil(state.pending)
        XCTAssertEqual(state.phase, .waiting)
    }

    func testChangedSessionRejectsLegacyQueuedTargetAndOldCompletion() {
        var state = NotificationRouteState()
        state.enqueue(target(), currentUserID: userID)
        XCTAssertNil(state.begin(userID: UUID(), blocked: false))
        state.enqueue(target(), currentUserID: userID)
        let request = state.begin(userID: userID, blocked: false)!
        state.finish(request, currentUserID: UUID(), succeeded: true, exists: true)
        XCTAssertEqual(state.phase, .loading)
    }

    func testOtherOwnerIsNeutralMissingWithoutReadingTheirRecord() {
        var state = NotificationRouteState()
        state.enqueue(target(owner: UUID()), currentUserID: nil)
        XCTAssertNotNil(state.begin(userID: userID, blocked: false))
        XCTAssertEqual(state.phase, .missing)
    }

    func testUnknownAndMalformedPayloadsAreIgnoredLegacyPayloadStillAccepted() {
        XCTAssertNil(NotificationTarget(userInfo: ["kind": "unknown", "item_id": UUID().uuidString]))
        XCTAssertNil(NotificationTarget(userInfo: ["kind": "task", "item_id": "bad"]))
        XCTAssertNil(NotificationTarget(userInfo: ["kind": "task", "item_id": UUID().uuidString, "user_id": "bad"]))
        XCTAssertNil(target().userID)
        XCTAssertEqual(target("selection").kind, .selection)
    }

    @MainActor
    func testPresentationProbeDefersForModalAndDetachedView() {
        XCTAssertTrue(NotificationPresentationProbe.isBlocked(nil))
        let root = UIViewController()
        XCTAssertTrue(NotificationPresentationProbe.isBlocked(root))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = root
        window.isHidden = false
        defer { window.isHidden = true }
        root.loadViewIfNeeded()
        XCTAssertFalse(NotificationPresentationProbe.isBlocked(root))
        let editor = UIViewController()
        root.present(editor, animated: false)
        XCTAssertTrue(NotificationPresentationProbe.isBlocked(root))
        XCTAssertTrue(root.presentedViewController === editor)
        editor.dismiss(animated: false)
    }

    @MainActor
    func testPendingPersistencePreservesOwnerAndResetRemovesIt() {
        defer { PendingNotificationStore.clear() }
        let item = target(owner: userID)
        PendingNotificationStore.save(userInfo: ["kind": "task", "item_id": item.itemID.uuidString,
                                                "user_id": userID.uuidString])
        XCTAssertEqual(NotificationTarget(userInfo: PendingNotificationStore.take()!), item)
        XCTAssertNil(PendingNotificationStore.take())
        PendingNotificationStore.save(userInfo: ["kind": "task", "item_id": item.itemID.uuidString])
        XCTAssertNil(NotificationTarget(userInfo: PendingNotificationStore.take()!)?.userID)
        PendingNotificationStore.save(userInfo: ["kind": "task", "item_id": item.itemID.uuidString])
        AppRouter().reset()
        XCTAssertNil(PendingNotificationStore.take())
    }
}
