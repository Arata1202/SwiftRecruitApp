import SwiftUI
import UIKit
import XCTest
@testable import SwiftRecruitApp

@MainActor
final class HomeEmptyRefreshTests: XCTestCase {
    func testActualEmptyHomeMountsContentInsideNavigationAndTabBars() async throws {
        let appeared = expectation(description: "Home appeared")
        let store = RecruitStore(repository: nil, notifications: LocalNotificationService())
        let root = TabView {
            HomeView().tabItem { Label("ホーム", systemImage: "house") }
        }
        .environment(AppSession(client: nil))
        .environment(AppRouter())
        .environment(store)
        .onAppear { appeared.fulfill() }
        let controller = UIHostingController(rootView: root)
        let window = mount(controller)
        defer { window.isHidden = true; window.rootViewController = nil }
        await fulfillment(of: [appeared], timeout: 3)
        window.layoutIfNeeded()
        let native = try XCTUnwrap(findRefreshController(controller))
        native.view.layoutIfNeeded()
        XCTAssertGreaterThan(native.host.view.bounds.height, 200)
        XCTAssertGreaterThan(native.host.view.bounds.width, 300)
        XCTAssertNotNil(native.host.view.window)
        let before = native.host.view.bounds.size
        native.refreshControl.beginRefreshing()
        native.refreshControl.sendActions(for: .valueChanged)
        await native.refreshTask?.value
        window.layoutIfNeeded()
        XCTAssertEqual(native.host.view.bounds.size, before)
        XCTAssertFalse(native.refreshControl.isRefreshing)
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Actual empty Home with navigation and tab bars"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func findRefreshController(_ controller: UIViewController) -> HomeEmptyRefreshController? {
        if let native = controller as? HomeEmptyRefreshController { return native }
        for child in controller.children {
            if let native = findRefreshController(child) { return native }
        }
        return nil
    }

    func testEmptyContentHasVisibleViewportAndDoesNotResizeWithRefreshInset() {
        let controller = HomeEmptyRefreshController(content: content, reload: {})
        let window = mount(controller)
        defer { window.isHidden = true }
        let initialFrame = controller.host.view.frame
        XCTAssertGreaterThan(initialFrame.width, 300)
        XCTAssertGreaterThan(initialFrame.height, 400)
        XCTAssertFalse(controller.host.view.hasAmbiguousLayout)
        XCTAssertTrue(controller.scrollView.alwaysBounceVertical)

        // Model the inset changes made by UIRefreshControl, not a finger gesture.
        controller.refreshControl.beginRefreshing()
        controller.scrollView.contentInset.top = 64
        controller.scrollView.setContentOffset(CGPoint(x: 0, y: -64), animated: false)
        window.layoutIfNeeded()
        XCTAssertEqual(controller.host.view.frame.size, initialFrame.size)
        controller.refreshControl.endRefreshing()
        controller.scrollView.contentInset.top = 0
        controller.scrollView.setContentOffset(.zero, animated: false)
        window.layoutIfNeeded()
        XCTAssertEqual(controller.host.view.frame, initialFrame)
        XCTAssertTrue(controller.host.view.point(inside: CGPoint(x: initialFrame.midX, y: initialFrame.midY), with: nil))
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Empty Home native viewport"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testRefreshEndsAfterReloadAndIgnoresDuplicateRequests() async {
        let started = expectation(description: "reload started")
        var continuation: CheckedContinuation<Void, Never>?
        var calls = 0
        let controller = HomeEmptyRefreshController(content: content) {
            calls += 1
            await withCheckedContinuation { continuation = $0; started.fulfill() }
        }
        controller.loadViewIfNeeded()
        controller.refreshControl.beginRefreshing()
        controller.refreshControl.sendActions(for: .valueChanged)
        await fulfillment(of: [started], timeout: 2)
        let pending = controller.refreshTask
        controller.refreshControl.sendActions(for: .valueChanged)
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(controller.refreshControl.isRefreshing)
        continuation?.resume()
        await pending?.value
        XCTAssertFalse(controller.refreshControl.isRefreshing)
        XCTAssertNil(controller.refreshTask)
    }

    func testRemovalCancelsRefreshWithoutOldCompletionEndingNewRefresh() async {
        let firstStarted = expectation(description: "first reload")
        let secondStarted = expectation(description: "second reload")
        var first: CheckedContinuation<Void, Never>?
        var second: CheckedContinuation<Void, Never>?
        let controller = HomeEmptyRefreshController(content: content) {
            await withCheckedContinuation { first = $0; firstStarted.fulfill() }
        }
        controller.loadViewIfNeeded()
        controller.refresh()
        await fulfillment(of: [firstStarted], timeout: 2)
        let oldTask = controller.refreshTask
        controller.cancelRefresh()
        controller.reload = {
            await withCheckedContinuation { second = $0; secondStarted.fulfill() }
        }
        controller.refreshControl.beginRefreshing()
        controller.refresh()
        await fulfillment(of: [secondStarted], timeout: 2)
        first?.resume()
        await oldTask?.value
        XCTAssertNotNil(controller.refreshTask)
        XCTAssertTrue(controller.refreshControl.isRefreshing)
        let newTask = controller.refreshTask
        second?.resume()
        await newTask?.value
        XCTAssertNil(controller.refreshTask)
        XCTAssertFalse(controller.refreshControl.isRefreshing)
    }

    func testNativeRefreshReturnsToRestWithoutResettingOffset() async {
        let controller = HomeEmptyRefreshController(content: content, reload: {})
        let window = mount(controller)
        defer { window.isHidden = true; window.rootViewController = nil }
        controller.refreshControl.beginRefreshing()
        window.layoutIfNeeded()
        controller.scrollView.setContentOffset(
            CGPoint(x: 0, y: -controller.scrollView.adjustedContentInset.top), animated: false)
        controller.refreshControl.sendActions(for: .valueChanged)
        await controller.refreshTask?.value
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            abs(controller.scrollView.contentOffset.y + controller.scrollView.adjustedContentInset.top) < 1
                && !controller.refreshControl.isRefreshing
        }, object: nil)
        await fulfillment(of: [settled], timeout: 3)
        XCTAssertGreaterThan(controller.host.view.bounds.height, 400)
    }

    func testTallContentCanScrollRatherThanBeingClipped() {
        let controller = HomeEmptyRefreshController(
            content: AnyView(Text("内容").frame(height: 1200)), reload: {})
        let window = mount(controller)
        defer { window.isHidden = true }
        XCTAssertGreaterThanOrEqual(controller.scrollView.contentSize.height, 1200)
        XCTAssertGreaterThan(controller.scrollView.contentSize.height, controller.scrollView.bounds.height)
    }

    private var content: AnyView {
        AnyView(ContentUnavailableView {
            Label("就活管理を始めましょう", systemImage: "briefcase")
        } description: {
            Text("企業の選考や期限付きのToDoをまとめて確認できます。")
        } actions: {
            Button("企業を追加") {}.buttonStyle(.borderedProminent)
            Button("ToDoを追加") {}.buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 100))
    }

    private func mount(_ controller: UIViewController) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        window.setNeedsLayout()
        window.layoutIfNeeded()
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        return window
    }
}
