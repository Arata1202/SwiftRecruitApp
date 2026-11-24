import XCTest
import UserNotifications
@testable import SwiftRecruitApp

final class AppDelegateNotificationTests: XCTestCase {
    @MainActor
    func testDefaultTapsCompleteOnceOnMainAfterSavingAndPosting() {
        for kind in ["task", "selection"] {
            for background in [false, true] {
                let info = ["kind": kind, "item_id": UUID().uuidString,
                            "company_id": UUID().uuidString, "user_id": UUID().uuidString]
                checkResponse(info: info, action: UNNotificationDefaultActionIdentifier,
                              background: background, expected: info)
            }
        }
    }

    @MainActor
    func testLegacyPayloadStillRoutesWithoutOwnerOrCompany() {
        let info = ["kind": "task", "item_id": UUID().uuidString]
        checkResponse(info: info, action: UNNotificationDefaultActionIdentifier,
                      background: true, expected: info)
    }

    @MainActor
    func testMalformedPayloadsCompleteOnceOnMainWithoutRouting() {
        for info: [AnyHashable: Any] in [[:], ["kind": "task"], ["item_id": "id"],
                                       ["kind": "task", "user_id": 42, "item_id": UUID().uuidString],
                                       ["kind": "unknown", "item_id": UUID().uuidString], ["kind": "task", "item_id": "invalid"],
                                       ["kind": 42, "item_id": "id"], ["kind": "task", "item_id": 42]] {
            for background in [false, true] {
                checkResponse(info: info, action: UNNotificationDefaultActionIdentifier,
                              background: background, expected: nil)
            }
        }
    }

    @MainActor
    func testDismissAndCustomActionsCompleteOnceOnMainWithoutRouting() {
        for action in [UNNotificationDismissActionIdentifier, "custom-action"] {
            for background in [false, true] {
                checkResponse(info: ["kind": "task", "item_id": UUID().uuidString],
                              action: action, background: background, expected: nil)
            }
        }
    }

    @MainActor
    func testForegroundCompletesOnceOnMainWithBannerAndSound() {
        for background in [false, true] {
            let delegate = AppDelegate()
            let done = expectation(description: "foreground completion")
            done.assertForOverFulfill = true
            var count = 0
            Self.invokeForeground(delegate: delegate, background: background) { options in
                XCTAssertTrue(Thread.isMainThread)
                count += 1
                XCTAssertEqual(options, [.banner, .sound])
                done.fulfill()
            }
            wait(for: [done], timeout: 2)
            drainMainQueue()
            XCTAssertEqual(count, 1)
        }
    }

    @MainActor
    private func checkResponse(info: [AnyHashable: Any], action: String,
                               background: Bool, expected: [String: String]?) {
        PendingNotificationStore.clear()
        defer { PendingNotificationStore.clear() }
        // Ignored/malformed responses must not overwrite an existing cold tap.
        let previous = ["kind": "task", "item_id": UUID().uuidString]
        PendingNotificationStore.save(userInfo: previous)
        let delegate = AppDelegate()
        let done = expectation(description: "response completion")
        done.assertForOverFulfill = true
        var completionCount = 0
        var postCount = 0
        let token = NotificationCenter.default.addObserver(
            forName: .didReceiveRecruitNotification, object: nil, queue: nil
        ) { event in
            XCTAssertTrue(Thread.isMainThread)
            postCount += 1
            XCTAssertEqual(completionCount, 0)
            XCTAssertNotNil(expected)
            XCTAssertEqual(event.userInfo as? [String: String], expected)
            // Synchronous observer must see the saved payload before completion.
            XCTAssertEqual(PendingNotificationStore.take() as? [String: String], expected)
            if let expected {
                XCTAssertNotNil(NotificationTarget(userInfo: expected))
            }
        }
        defer { NotificationCenter.default.removeObserver(token) }
        Self.invokeResponse(delegate: delegate, info: info, action: action, background: background) {
            XCTAssertTrue(Thread.isMainThread)
            completionCount += 1
            XCTAssertEqual(postCount, expected == nil ? 0 : 1)
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
        drainMainQueue()
        XCTAssertEqual(completionCount, 1)
        XCTAssertEqual(postCount, expected == nil ? 0 : 1)
        XCTAssertEqual(PendingNotificationStore.take() as? [String: String], expected == nil ? previous : nil)
    }

    // Build the dispatched closures outside actor-isolated test methods. The
    // supplied completions only run on main, where the result counters live.
    private nonisolated static func invokeResponse(
        delegate: AppDelegate, info: [AnyHashable: Any], action: String,
        background: Bool, completion: @escaping () -> Void
    ) {
        let invoke = {
            XCTAssertEqual(Thread.isMainThread, !background)
            delegate.handleNotificationResponse(actionIdentifier: action, contentUserInfo: info,
                                                completionHandler: completion)
        }
        if background { DispatchQueue.global(qos: .userInitiated).async(execute: DispatchWorkItem(block: invoke)) }
        else { invoke() }
    }

    private nonisolated static func invokeForeground(
        delegate: AppDelegate, background: Bool,
        completion: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let invoke = {
            XCTAssertEqual(Thread.isMainThread, !background)
            delegate.completeForegroundNotification(completionHandler: completion)
        }
        if background { DispatchQueue.global(qos: .userInitiated).async(execute: DispatchWorkItem(block: invoke)) }
        else { invoke() }
    }

    @MainActor
    private func drainMainQueue() {
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 2)
    }
}
