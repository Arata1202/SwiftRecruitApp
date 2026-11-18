import Foundation
import XCTest
@testable import SwiftRecruitApp

final class EditorDraftChangesTests: XCTestCase {
    func testInitialDraftsIncludingPrefilledQuestionsAndInterviewDatesAreClean() {
        let template = ESTemplateDraft(category: .motivation)
        let information = CompanyInformationDraft(category: .interview)

        XCTAssertFalse(template.hasChanges(comparedTo: template))
        XCTAssertFalse(information.hasChanges(comparedTo: information))
    }

    func testTemplateProtectsEveryEditableFieldAndBecomesCleanWhenReverted() {
        var initial = ESTemplateDraft(category: .motivation)
        initial.title = "志望動機"
        initial.body = "元の本文"
        for field in ["category", "title", "body"] {
            var edited = initial
            switch field {
            case "category": edited.category = .custom
            case "title": edited.title += "変更"
            default: edited.body += String(repeating: "長文", count: 1_000)
            }
            XCTAssertTrue(edited.hasChanges(comparedTo: initial), field)
            edited = initial
            XCTAssertFalse(edited.hasChanges(comparedTo: initial), field)
        }
    }

    func testCompanyInformationProtectsEveryEditableFieldAndBecomesCleanWhenReverted() {
        var initial = CompanyInformationDraft(category: .interview)
        initial.title = "面接"
        initial.body = "元の記録"
        initial.date = makeDate(day: 12)
        for field in ["category", "title", "body", "hasDate", "date"] {
            var edited = initial
            switch field {
            case "category": edited.category = .research
            case "title": edited.title += "変更"
            case "body": edited.body += String(repeating: "長文", count: 1_000)
            case "hasDate": edited.hasDate = false
            default: edited.date = makeDate(day: 13)
            }
            XCTAssertTrue(edited.hasChanges(comparedTo: initial), field)
            edited = initial
            XCTAssertFalse(edited.hasChanges(comparedTo: initial), field)
        }
    }

    func testWhitespaceOnlyChangesAreStillProtected() {
        let template = ESTemplateDraft()
        var editedTemplate = template
        editedTemplate.body = " \n"
        XCTAssertTrue(editedTemplate.hasChanges(comparedTo: template))


        let information = CompanyInformationDraft()
        var editedInformation = information
        editedInformation.title = " "
        XCTAssertTrue(editedInformation.hasChanges(comparedTo: information))
    }

    func testDisabledCompanyDateDoesNotCauseFalseChanges() {
        var initial = CompanyInformationDraft(category: .research)
        initial.date = makeDate(day: 12)
        var edited = initial
        edited.date = makeDate(day: 13)
        XCTAssertFalse(edited.hasChanges(comparedTo: initial))

        edited.hasDate = true
        XCTAssertTrue(edited.hasChanges(comparedTo: initial))
        edited.hasDate = false
        XCTAssertFalse(edited.hasChanges(comparedTo: initial))
    }

    func testCompanyDateComparesCalendarDayNotHiddenTime() {
        var initial = CompanyInformationDraft(category: .interview)
        initial.date = makeDate(day: 12, hour: 9)
        var edited = initial
        edited.date = makeDate(day: 12, hour: 18)
        XCTAssertFalse(edited.hasChanges(comparedTo: initial))
        edited.date = makeDate(day: 13, hour: 9)
        XCTAssertTrue(edited.hasChanges(comparedTo: initial))
    }

    private func makeDate(day: Int, hour: Int = 12) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }
}
