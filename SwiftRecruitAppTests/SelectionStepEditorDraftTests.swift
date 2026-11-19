import Foundation
import XCTest
@testable import SwiftRecruitApp

final class SelectionStepEditorDraftTests: XCTestCase {
    func testInternshipTypeRoundTripDisplayAndWrite() throws {
        let type = SelectionType.internship
        XCTAssertEqual(type.title, "インターンシップ")
        XCTAssertEqual(type.defaultDateKind, .schedule)
        XCTAssertEqual(try JSONDecoder().decode(SelectionType.self, from: JSONEncoder().encode(type)), type)
        XCTAssertTrue(SelectionType.allCases.contains(type))
        var draft = SelectionStepDraft()
        draft.setType(type)
        XCTAssertEqual(draft.dateKind, .schedule)
        XCTAssertEqual(try encodedObject(SelectionStepWrite(userID: UUID(), companyID: UUID(), draft: draft))["type"] as? String, "internship")
        XCTAssertEqual(try encodedObject(SelectionStepUpdate(draft: draft))["type"] as? String, "internship")
        var step = makeStep()
        step.type = type
        step.customTitle = nil
        XCTAssertEqual(step.displayTitle, "インターンシップ")
        XCTAssertEqual(SelectionStepDraft(step: step).type, type)
    }

    func testNewSelectionTypeChoosesDateKindExceptOther() {
        for type in SelectionType.allCases where type != .other {
            var draft = SelectionStepDraft()
            draft.setType(type)
            XCTAssertEqual(draft.dateKind, type.defaultDateKind)
        }
        var draft = SelectionStepDraft()
        draft.setType(.document)
        XCTAssertEqual(draft.dateKind, .deadline)
        XCTAssertEqual(draft.notificationTimedCustom, .relative(1, unit: .days).withNotificationClock(hour: 9, minute: 0))
        draft.setType(.other)
        XCTAssertEqual(draft.dateKind, .deadline)
        draft.setType(.interview)
        XCTAssertEqual(draft.dateKind, .schedule)
        draft.setType(.other)
        XCTAssertEqual(draft.dateKind, .schedule)
        XCTAssertNil(draft.notificationTimedCustom)
    }

    func testExplicitDateKindSurvivesAllTypeChoices() {
        for kind in SelectionDateKind.allCases {
            var draft = SelectionStepDraft()
            draft.setDateKind(kind)
            for type in SelectionType.allCases {
                draft.setType(type)
                XCTAssertEqual(draft.dateKind, kind)
            }
        }
    }

    func testExistingDateKindAndDraftCancelStayUnchanged() {
        let initial = SelectionStepDraft(step: makeStep())
        var draft = initial
        let kind = draft.dateKind
        let date = draft.date
        for type in SelectionType.allCases {
            draft.setType(type)
            XCTAssertEqual(draft.dateKind, kind)
            XCTAssertEqual(draft.date, date)
        }
        var fresh = SelectionStepDraft()
        let original = fresh
        fresh.setType(.document)
        XCTAssertNotEqual(fresh.dateKind, original.dateKind)
        fresh = original
        XCTAssertEqual(fresh.dateKind, .schedule)
        fresh.setType(.aptitude)
        XCTAssertEqual(fresh.dateKind, .deadline)
    }

    func testCustomTitleSupplementsTypeAndFallsBackForBlankTitle() {
        for type in SelectionType.allCases {
            var step = makeStep()
            step.type = type
            step.customTitle = "一次面接"
            let expected = type == .other || type == .interview ? "一次面接" : "\(type.title)／一次面接"
            XCTAssertEqual(step.displayTitle, expected)
            XCTAssertEqual(SelectionStepDraft(step: step).customTitle, "一次面接")
            let blankTitles: [String?] = [nil, "", "  \n "]
            for title in blankTitles {
                step.customTitle = title
                XCTAssertEqual(step.displayTitle, type.title)
            }
        }
    }

    func testSupplementAndExistingTypeTitlesDoNotDuplicateOrMutateStoredTitle() {
        for type in SelectionType.allCases {
            var step = makeStep()
            step.type = type
            step.customTitle = "一次"
            XCTAssertEqual(step.displayTitle, type == .other ? "一次" : "\(type.title)／一次")
            XCTAssertEqual(step.customTitle, "一次")
            for title in [type.title, "一次\(type.title)", "\(type.title)／一次"] {
                step.customTitle = title
                XCTAssertEqual(step.displayTitle, title)
                XCTAssertEqual(SelectionStepDraft(step: step).customTitle, title)
            }
        }
    }

    func testWriteAndUpdatePersistCustomTitleForEveryType() throws {
        for type in SelectionType.allCases {
            var draft = SelectionStepDraft()
            draft.type = type
            draft.customTitle = "  一次面接  "
            let write = SelectionStepWrite(userID: UUID(), companyID: UUID(), draft: draft)
            let update = SelectionStepUpdate(draft: draft)
            XCTAssertEqual(write.customTitle, "一次面接")
            XCTAssertEqual(update.customTitle, "一次面接")
            XCTAssertEqual(try encodedObject(write)["custom_title"] as? String, "一次面接")
            XCTAssertEqual(try encodedObject(update)["custom_title"] as? String, "一次面接")
        }
    }

    func testOverlongOtherTitleSurvivesTypeSwitchAndCanBeShortened() throws {
        for type in SelectionType.allCases where type != .other {
            var draft = SelectionStepDraft()
            draft.type = .other
            let overlong = String(repeating: "選", count: 121)
            draft.customTitle = overlong
            XCTAssertTrue(draft.isCustomTitleTooLong)
            draft.type = type
            XCTAssertEqual(draft.customTitle, overlong)
            XCTAssertTrue(draft.isCustomTitleTooLong)

            // The editor's recovery button returns to the editable title without changing it.
            draft.type = .other
            XCTAssertEqual(draft.customTitle, overlong)
            XCTAssertTrue(draft.isCustomTitleTooLong)
            let shortened = String(repeating: "選", count: 120)
            draft.customTitle = shortened
            XCTAssertFalse(draft.isCustomTitleTooLong)
            draft.type = type
            XCTAssertFalse(draft.isCustomTitleTooLong)
            XCTAssertEqual(draft.customTitle, shortened)
            XCTAssertEqual(try encodedObject(SelectionStepUpdate(draft: draft))["custom_title"] as? String, shortened)
        }
    }

    func testTitleLengthUsesTrimmedUnicodeScalarsForEveryType() {
        // Combining marks and joined emoji must not be counted as a single character.
        for unit in ["選", "😀", "e\u{301}", "👩‍💻"] {
            let boundary = String(repeating: unit, count: 120 / unit.unicodeScalars.count)
            XCTAssertEqual(boundary.unicodeScalars.count, 120)
            for type in SelectionType.allCases {
                var draft = SelectionStepDraft()
                draft.type = type
                draft.customTitle = "  \n" + boundary + "\n  "
                XCTAssertFalse(draft.isCustomTitleTooLong)
                draft.customTitle = "  \n" + boundary + "選\n  "
                XCTAssertTrue(draft.isCustomTitleTooLong)
            }
        }
    }

    func testExistingNormalTitleRemainsValidAndPersistsAfterTypeRoundTrip() throws {
        for type in SelectionType.allCases where type != .other {
            var step = makeStep()
            step.type = type
            step.customTitle = "一次面接"
            var draft = SelectionStepDraft(step: step)
            XCTAssertFalse(draft.isCustomTitleTooLong)
            draft.type = .other
            draft.type = type
            XCTAssertEqual(draft.customTitle, step.customTitle)
            XCTAssertFalse(draft.isCustomTitleTooLong)
            XCTAssertEqual(try encodedObject(SelectionStepUpdate(draft: draft))["custom_title"] as? String, step.customTitle)
        }
    }

    func testClearingOptionalTitleExplicitlyEncodesNullOnUpdate() throws {
        var draft = SelectionStepDraft()
        draft.customTitle = "  \n "
        XCTAssertNil(SelectionStepWrite(userID: UUID(), companyID: UUID(), draft: draft).customTitle)
        XCTAssertTrue(try encodedObject(SelectionStepUpdate(draft: draft))["custom_title"] is NSNull)
    }

    func testNewDraftDefaultsToScheduledInterviewWithoutTime() {
        let before = Date()
        let draft = SelectionStepDraft()
        let after = Date()
        XCTAssertEqual(draft.type, .interview)
        XCTAssertEqual(draft.status, .scheduled)
        XCTAssertEqual(draft.dateKind, .schedule)
        XCTAssertFalse(draft.hasTime)
        XCTAssertTrue(draft.notificationEnabled)
        XCTAssertGreaterThanOrEqual(draft.date, before)
        XCTAssertLessThanOrEqual(draft.date, after)
    }

    func testChangingTypePreservesChosenDateKindDateAndTime() {
        let selectedDate = Date(timeIntervalSince1970: 2_000_000_000)
        for kind in SelectionDateKind.allCases {
            var draft = SelectionStepDraft(date: selectedDate)
            draft.dateKind = kind
            draft.hasTime = true
            for type in SelectionType.allCases {
                draft.type = type
                XCTAssertEqual(draft.dateKind, kind)
                XCTAssertEqual(draft.date, selectedDate)
                XCTAssertTrue(draft.hasTime)
                XCTAssertEqual(draft.status, .scheduled)
            }
        }
    }

    func testExistingDraftPreservesStatusTitleDateAndNotificationPreference() {
        for status in SelectionStepStatus.allCases {
            for enabled in [true, false] {
                var step = makeStep()
                step.status = status
                step.notificationEnabled = enabled
                var draft = SelectionStepDraft(step: step)
                XCTAssertEqual(draft.status, status)
                XCTAssertEqual(draft.customTitle, step.customTitle)
                XCTAssertEqual(draft.date, step.startsAt)
                XCTAssertEqual(draft.dateKind, .schedule)
                draft.status = .cancelled
                XCTAssertEqual(SelectionStepUpdate(draft: draft).notificationEnabled, enabled)
                draft.status = .scheduled
                XCTAssertEqual(SelectionStepUpdate(draft: draft).notificationEnabled, enabled)
                XCTAssertEqual(step.status, status)
            }
        }
    }

    func testExistingDeadlineIsNotReplacedByTypeDefault() {
        var step = makeStep()
        step.deadlineAt = step.startsAt
        step.startsAt = nil
        let draft = SelectionStepDraft(step: step)
        XCTAssertEqual(draft.type, .interview)
        XCTAssertEqual(draft.dateKind, .deadline)
        XCTAssertEqual(draft.date, step.deadlineAt)
    }

    func testNotificationDescriptionsRespectEachCalculatorBoundary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 9 * 3_600))
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2030, month: 1, day: 3, hour: 12)))
        let early = date.addingTimeInterval(-172_800)
        for kind in SelectionDateKind.allCases {
            for hasTime in [true, false] {
                var draft = SelectionStepDraft(date: date)
                draft.dateKind = kind
                draft.hasTime = hasTime
                draft.notificationTimedPreset = nil
                draft.notificationDatePreset = nil
                let boundary = try XCTUnwrap(kind == .deadline
                    ? NotificationScheduleCalculator.selectionDeadlineDate(deadlineAt: date, hasTime: hasTime, calendar: calendar, now: early)
                    : NotificationScheduleCalculator.selectionStartDate(startsAt: date, hasTime: hasTime, calendar: calendar, now: early))
                let before = try XCTUnwrap(draft.notificationDescription(calendar: calendar, now: boundary.addingTimeInterval(-1)))
                XCTAssertTrue(before.contains("通知予定"))
                for now in [boundary, boundary.addingTimeInterval(1)] {
                    let description = try XCTUnwrap(draft.notificationDescription(calendar: calendar, now: now))
                    XCTAssertTrue(description.contains("通知されません"))
                    XCTAssertFalse(description.contains("通知予定"))
                }
            }
        }
    }

    func testNotificationDescriptionIsAbsentWhenDisabledOrInactive() {
        var draft = SelectionStepDraft(date: Date().addingTimeInterval(172_800))
        draft.notificationEnabled = false
        XCTAssertNil(draft.notificationDescription())
        draft.notificationEnabled = true
        for status in [SelectionStepStatus.completed, .cancelled] {
            draft.status = status
            XCTAssertNil(draft.notificationDescription())
            XCTAssertTrue(draft.notificationEnabled)
        }
    }

    private func encodedObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    }

    private func makeStep() -> SelectionStep {
        let date = Date(timeIntervalSince1970: 2_000_000_000)
        return SelectionStep(
            id: UUID(), userID: UUID(), companyID: UUID(), type: .interview,
            customTitle: "一次面接", startsAt: date, startsHasTime: true,
            deadlineAt: nil, deadlineHasTime: false, status: .scheduled,
            memo: nil, notificationEnabled: true, createdAt: date, updatedAt: date
        )
    }
}
