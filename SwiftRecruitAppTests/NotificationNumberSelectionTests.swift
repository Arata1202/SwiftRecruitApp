import XCTest
@testable import SwiftRecruitApp

final class NotificationNumberSelectionTests: XCTestCase {
    func testSuggestionsIncludeExistingArbitraryValueWithoutChangingIt() {
        for (kind, value) in [(NotificationNumberSelection.Kind.minutes, 37), (.hours, 17), (.days, 11)] {
            let entry = NotificationNumberSelection(kind: kind, value: value)
            let choices = kind.choices(including: value)
            XCTAssertTrue(choices.contains(value))
            XCTAssertEqual(choices, choices.sorted())
            XCTAssertEqual(Set(choices).count, choices.count)
            XCTAssertEqual(entry.confirmedValue, value)
            XCTAssertFalse(entry.hasChanges)
            XCTAssertTrue(kind.suggestions.allSatisfy { kind.range.contains($0) })
        }
    }

    func testAllModelBoundsAreAcceptedAndOutsideValuesStayInvalid() {
        for kind in NotificationNumberSelection.Kind.allCases {
            var entry = NotificationNumberSelection(kind: kind, value: kind.range.lowerBound)
            for value in [kind.range.lowerBound, kind.range.upperBound] {
                entry.text = String(value)
                XCTAssertEqual(entry.confirmedValue, value)
                XCTAssertNil(entry.validationMessage)
            }
            for text in ["", "-1", "1.5", "abc", " 7", "999999999999999999999999", String(kind.range.upperBound + 1)] {
                entry.text = text
                XCTAssertNil(entry.confirmedValue)
                XCTAssertEqual(entry.validationMessage, kind.inputHint)
                XCTAssertEqual(entry.text, text)
            }
            entry.text = "0"
            XCTAssertEqual(entry.confirmedValue, kind == .days ? 0 : nil)
        }
    }

    func testManualEditingAndCancellationDoNotMutateDraft() {
        for custom in [CustomNotificationTiming.elapsed(37), .elapsed(17, unit: .hours), .calendar(daysBefore: 11, hour: 18, minute: 37)] {
            var draft = RecruitTaskDraft()
            draft.notificationTimedCustom = custom.mode == .elapsed ? custom : .elapsed(37)
            draft.notificationDateCustom = custom.mode == .calendar ? custom : .calendar(daysBefore: 11)
            let initial = draft
            var entry = NotificationNumberSelection(kind: .init(custom: custom), value: custom.value)
            for text in ["", "99999999", "23"] {
                entry.text = text
                XCTAssertTrue(entry.hasChanges)
                XCTAssertFalse(draft.hasChanges(comparedTo: initial))
            }
            // Cancel discards the local entry; reopening reflects the unchanged stored value.
            entry = NotificationNumberSelection(kind: .init(custom: custom), value: custom.value)
            XCTAssertFalse(entry.hasChanges)
            XCTAssertEqual(entry.confirmedValue, custom.value)
        }
    }

    func testExplicitConfirmationChangesOnlyNumberAndPreservesDayIntent() throws {
        for hasTime in [true, false] {
            for value in [0, 1, 23, 365] {
                var presentation = NotificationTimingPresentation()
                var custom = CustomNotificationTiming.calendar(daysBefore: 11, hour: 18, minute: 37)
                var entry = NotificationNumberSelection(kind: .days, value: custom.value)
                entry.text = String(value)
                presentation.editNumber(String(try XCTUnwrap(entry.confirmedValue)), custom: &custom, hasTime: hasTime)
                XCTAssertEqual(custom, .calendar(daysBefore: value, hour: 18, minute: 37))
                XCTAssertEqual(presentation.dayChoice(custom, hasTime: hasTime), .arbitrary)
            }
        }
        for unit in CustomNotificationTiming.Unit.allCases {
            var presentation = NotificationTimingPresentation()
            var custom = CustomNotificationTiming.elapsed(37, unit: unit)
            var entry = NotificationNumberSelection(kind: .init(custom: custom), value: custom.value)
            entry.text = "23"
            presentation.editNumber(String(try XCTUnwrap(entry.confirmedValue)), custom: &custom, hasTime: true)
            XCTAssertEqual(custom, .elapsed(23, unit: unit))
        }
    }

    func testOpeningOutOfRangeValueNeverNormalizesIt() {
        for kind in NotificationNumberSelection.Kind.allCases {
            let value = kind.range.upperBound + 1
            let entry = NotificationNumberSelection(kind: kind, value: value)
            XCTAssertTrue(kind.choices(including: value).contains(value))
            XCTAssertEqual(entry.text, String(value))
            XCTAssertFalse(entry.hasChanges)
            XCTAssertNil(entry.confirmedValue)
        }
    }
}
