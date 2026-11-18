import XCTest
@testable import SwiftRecruitApp

final class DateMetadataTests: XCTestCase {
    func testCalendarMetadataUsesOnlyKindAndTime() {
        let date = Date(timeIntervalSince1970: 2_000_000_000)
        for kind in ["予定", "締切", "期限"] {
            XCTAssertEqual(
                DateFormatting.calendarMetadata(kind: kind, date: date, hasTime: true),
                "\(kind) \(DateFormatting.time.string(from: date))"
            )
        }
    }

    func testDateOnlyCalendarMetadataDoesNotInventMidnightOrRepeatDay() {
        let date = Date(timeIntervalSince1970: 2_000_000_000)
        for kind in ["予定", "締切", "期限"] {
            XCTAssertEqual(
                DateFormatting.calendarMetadata(kind: kind, date: date, hasTime: false),
                "\(kind) 時刻未設定"
            )
        }
    }
}
