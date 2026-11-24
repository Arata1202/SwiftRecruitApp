import XCTest
@testable import SwiftRecruitApp

final class NotificationTimingPresentationTests: XCTestCase {
    func testOpeningAndReadingSelectionsNeverChangesDraft() {
        var draft = SelectionStepDraft()
        draft.notificationTimedCustom = .elapsed(45)
        draft.notificationDateCustom = .calendar(daysBefore: 1, hour: 18)
        let initial = draft
        for kind in [NotificationAnchor.selectionStart, .selectionDeadline, .taskDue] {
            for hasTime in [true, false] {
                let custom = hasTime ? draft.notificationTimedCustom : draft.notificationDateCustom
                XCTAssertEqual(NotificationTimingPresentation.selection(enabled: true, hasTime: hasTime, kind: kind,
                    timed: draft.notificationTimedPreset, date: draft.notificationDatePreset, custom: custom), "custom")
                XCTAssertEqual(NotificationTimingPresentation.selection(enabled: false, hasTime: hasTime, kind: kind,
                    timed: draft.notificationTimedPreset, date: draft.notificationDatePreset, custom: custom), "none")
            }
        }
        XCTAssertFalse(draft.hasChanges(comparedTo: initial))
    }
}
