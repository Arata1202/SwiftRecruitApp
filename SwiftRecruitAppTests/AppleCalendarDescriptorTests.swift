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

    func testAllDayEventEndsOnFollowingDay() throws {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date(timeIntervalSince1970: 2_000_000_000))
        let descriptor = AppleCalendarEventDescriptor(
            key: "test",
            title: "締切",
            notes: nil,
            startDate: start,
            hasTime: false,
            duration: 1_800
        )

        let expectedEnd = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: start))
        XCTAssertEqual(descriptor.endDate, expectedEnd)
    }
}
