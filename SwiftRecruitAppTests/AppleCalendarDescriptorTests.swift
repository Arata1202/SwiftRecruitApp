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

    func testTimedEventUsesProvidedDuration() {
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        let descriptor = AppleCalendarEventDescriptor(
            key: "test",
            title: "面接",
            notes: nil,
            startDate: start,
            hasTime: true,
            duration: 3_600
        )

        XCTAssertEqual(descriptor.endDate.timeIntervalSince(start), 3_600)
    }

    func testDeadlineCanUseThirtyMinuteDuration() {
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        let descriptor = AppleCalendarEventDescriptor(
            key: "deadline",
            title: "締切",
            notes: nil,
            startDate: start,
            hasTime: true,
            duration: 1_800
        )

        XCTAssertEqual(descriptor.endDate.timeIntervalSince(start), 1_800)
    }

    func testAllDayEventEndsOnFollowingDay() {
        let calendar = Calendar.current
        let start = calendar.date(from: DateComponents(year: 2030, month: 1, day: 2))!
        let descriptor = AppleCalendarEventDescriptor(
            key: "test",
            title: "締切",
            notes: nil,
            startDate: start,
            hasTime: false,
            duration: 1_800
        )

        XCTAssertEqual(calendar.dateComponents([.day], from: start, to: descriptor.endDate).day, 1)
    }
}
