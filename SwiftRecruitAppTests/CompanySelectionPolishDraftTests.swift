import Foundation
import XCTest
@testable import SwiftRecruitApp

final class CompanySelectionPolishDraftTests: XCTestCase {
    func testCompanyEditableFieldsAreProtectedAndRevertingIsClean() {
        let initial = CompanyDraft()
        XCTAssertFalse(initial.hasChanges(comparedTo: initial))
        for field in ["name", "status", "url", "memo"] {
            var edited = initial
            switch field {
            case "name": edited.name = "企業"
            case "status": edited.status = .active
            case "url": edited.url = "https://example.com"
            default: edited.memo = " \n"
            }
            XCTAssertTrue(edited.hasChanges(comparedTo: initial), field)
            edited = initial
            XCTAssertFalse(edited.hasChanges(comparedTo: initial), field)
        }
    }

    func testSelectionEditableFieldsAreProtectedAndRevertingIsClean() {
        var initial = SelectionStepDraft(date: date(day: 18))
        initial.customTitle = "一次"
        XCTAssertFalse(initial.hasChanges(comparedTo: initial))
        for field in ["type", "title", "dateKind", "date", "hasTime", "status", "memo", "notification"] {
            var edited = initial
            switch field {
            case "type": edited.type = .other
            case "title": edited.customTitle += "変更"
            case "dateKind": edited.dateKind = .deadline
            case "date": edited.date = date(day: 19)
            case "hasTime": edited.hasTime = true
            case "status": edited.status = .completed
            case "memo": edited.memo = " \n"
            default: edited.notificationEnabled = false
            }
            XCTAssertTrue(edited.hasChanges(comparedTo: initial), field)
            edited = initial
            XCTAssertFalse(edited.hasChanges(comparedTo: initial), field)
        }
    }

    func testDateOnlySelectionIgnoresHiddenTimeAndTimeToggleRoundTrip() {
        let initial = SelectionStepDraft(date: date(day: 18, hour: 9))
        var edited = initial
        edited.setHasTime(true, now: date(day: 18, hour: 17))
        XCTAssertTrue(edited.hasChanges(comparedTo: initial))
        edited.setHasTime(false)
        XCTAssertFalse(edited.hasChanges(comparedTo: initial))
        edited.date = date(day: 19, hour: 9)
        XCTAssertTrue(edited.hasChanges(comparedTo: initial))
    }

    func testTimedSelectionComparesVisibleMinuteNotHiddenSeconds() {
        var initial = SelectionStepDraft(date: date(day: 18, hour: 9))
        initial.hasTime = true
        var edited = initial
        edited.date += 30
        XCTAssertFalse(edited.hasChanges(comparedTo: initial))
        edited.date += 60
        XCTAssertTrue(edited.hasChanges(comparedTo: initial))
    }

    func testSelectionStatusIsDraftOnlyAndLegacyTitleSurvivesTypeChanges() {
        var initial = SelectionStepDraft(date: date(day: 18))
        initial.customTitle = "一次"
        var edited = initial
        edited.status = .completed
        XCTAssertEqual(initial.status, .scheduled)
        XCTAssertTrue(edited.hasChanges(comparedTo: initial))
        edited.status = .cancelled
        XCTAssertTrue(edited.hasChanges(comparedTo: initial))
        edited.status = .scheduled
        edited.type = .other
        edited.type = initial.type
        XCTAssertEqual(edited.customTitle, "一次")
        XCTAssertFalse(edited.hasChanges(comparedTo: initial))
    }

    private func date(day: Int, hour: Int = 12) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }
}
