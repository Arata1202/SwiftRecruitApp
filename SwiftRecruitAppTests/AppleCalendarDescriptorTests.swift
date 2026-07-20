import XCTest
@testable import SwiftRecruitApp

final class AppleCalendarDescriptorTests: XCTestCase {
    func testSelectionKeysSeparateScheduleAndDeadline() {
        let id = UUID()

        XCTAssertNotEqual(
            AppleCalendarService.selectionKey(id: id, kind: .start),
            AppleCalendarService.selectionKey(id: id, kind: .deadline)
        )
    }

    func testTimedEventDefaultsToOneHour() {
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        let descriptor = AppleCalendarEventDescriptor(
            key: "test",
            title: "面接",
            notes: nil,
            startDate: start,
            hasTime: true
        )

        XCTAssertEqual(descriptor.endDate.timeIntervalSince(start), 3_600)
    }

    func testAllDayEventEndsOnFollowingDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3_600)!
        let start = calendar.date(from: DateComponents(year: 2030, month: 1, day: 2))!
        let descriptor = AppleCalendarEventDescriptor(
            key: "test",
            title: "締切",
            notes: nil,
            startDate: start,
            hasTime: false
        )

        XCTAssertEqual(calendar.dateComponents([.day], from: start, to: descriptor.endDate).day, 1)
    }
}
