import Foundation
import XCTest
@testable import SwiftRecruitApp

@MainActor
final class TaskCompletionButtonAccessibilityTests: XCTestCase {
    func testIncompleteTaskAnnouncesItsTitleAndCompletionAction() {
        let button = TaskCompletionButton(task: makeTask(isCompleted: false)) {}

        XCTAssertEqual(button.completionAccessibilityLabel, "「面接の準備」を完了にする")
    }

    func testCompletedTaskAnnouncesItsTitleAndReopenAction() {
        let button = TaskCompletionButton(task: makeTask(isCompleted: true)) {}

        XCTAssertEqual(button.completionAccessibilityLabel, "「面接の準備」を未完了に戻す")
    }

    func testWorkingTaskAnnouncesItsTitleInsteadOfEitherAction() {
        for isCompleted in [false, true] {
            let button = TaskCompletionButton(
                task: makeTask(isCompleted: isCompleted),
                isDisabled: true,
                isWorking: true
            ) {}

            XCTAssertEqual(button.completionAccessibilityLabel, "「面接の準備」を更新中")
        }
    }

    private func makeTask(isCompleted: Bool) -> RecruitTask {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        return RecruitTask(
            id: UUID(),
            userID: UUID(),
            companyID: nil,
            title: "面接の準備",
            memo: nil,
            dueAt: nil,
            dueHasTime: false,
            completedAt: isCompleted ? now : nil,
            notificationEnabled: false,
            createdAt: now,
            updatedAt: now
        )
    }
}
