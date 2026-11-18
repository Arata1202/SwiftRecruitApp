import XCTest
@testable import SwiftRecruitApp

final class SelectionScheduleRangeTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private func date(_ year: Int = 2026, _ month: Int = 12, _ day: Int = 31, _ hour: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func step(timed: Bool = true, end: Date? = nil) -> SelectionStep {
        let start = date()
        return SelectionStep(
            id: UUID(), userID: UUID(), companyID: UUID(), type: .interview, customTitle: nil,
            startsAt: start, startsOn: timed ? nil : LocalDate(date: start, calendar: calendar),
            endsAt: timed ? end : nil, endsOn: timed ? nil : end.map { LocalDate(date: $0, calendar: calendar) },
            startsHasTime: timed, deadlineAt: nil, deadlineHasTime: false, status: .scheduled,
            memo: nil, notificationEnabled: true, createdAt: start, updatedAt: start
        )
    }

    private func object<T: Encodable>(_ value: T) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    }

    func testLegacyMissingEndDecodesAndEditorDoesNotInventEnd() throws {
        let original = step()
        var json = try object(original)
        json.removeValue(forKey: "ends_at")
        json.removeValue(forKey: "ends_on")
        let decoded = try JSONDecoder().decode(SelectionStep.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.endsAt)
        XCTAssertNil(decoded.endsOn)
        XCTAssertEqual(decoded.startsAt, original.startsAt)
        XCTAssertFalse(SelectionStepDraft(step: decoded).hasEnd)
        XCTAssertTrue(decoded.covers(day: date(), calendar: calendar))
        XCTAssertFalse(decoded.covers(day: date(2027, 1, 1), calendar: calendar))
    }

    func testTimedValidationAndDateOnlyComparisonIgnoreHiddenTime() {
        var draft = SelectionStepDraft(date: date())
        draft.hasEnd = true
        draft.hasTime = true
        draft.endDate = draft.date.addingTimeInterval(-60)
        XCTAssertFalse(draft.isValidRange(calendar: calendar))
        draft.endDate = draft.date
        XCTAssertTrue(draft.isValidRange(calendar: calendar))
        draft.endDate = date(2027, 1, 2)
        XCTAssertTrue(draft.isValidRange(calendar: calendar))
        draft.hasTime = false
        draft.endDate = date(2026, 12, 31, 0)
        XCTAssertTrue(draft.isValidRange(calendar: calendar))
        draft.endDate = date(2026, 12, 30)
        XCTAssertFalse(draft.isValidRange(calendar: calendar))
        draft.hasEnd = false
        XCTAssertTrue(draft.isValidRange(calendar: calendar))
        draft.hasEnd = true
        draft.dateKind = .deadline
        XCTAssertTrue(draft.isValidRange(calendar: calendar))
    }

    func testEndToggleAndDirtyCheckPreserveDraftAndIgnoreHiddenEnd() {
        var draft = SelectionStepDraft(date: date())
        let initial = draft
        draft.setHasEnd(true)
        XCTAssertEqual(draft.endDate, draft.date)
        XCTAssertTrue(draft.hasChanges(comparedTo: initial, calendar: calendar))
        draft.endDate = date(2027, 1, 2)
        draft.setHasEnd(false)
        XCTAssertFalse(draft.hasChanges(comparedTo: initial, calendar: calendar))
        draft.setHasEnd(true)
        XCTAssertEqual(draft.endDate, date(2027, 1, 2))
        var changed = draft
        changed.endDate = date(2027, 1, 3)
        XCTAssertTrue(changed.hasChanges(comparedTo: draft, calendar: calendar))
        changed = draft
        changed.endDate = draft.endDate.addingTimeInterval(60)
        XCTAssertFalse(changed.hasChanges(comparedTo: draft, calendar: calendar))
    }

    func testWriteAndUpdatePersistOnlyMatchingEndRepresentation() throws {
        var draft = SelectionStepDraft(date: date())
        draft.hasEnd = true
        draft.endDate = date(2027, 1, 2)
        for timed in [false, true] {
            draft.hasTime = timed
            let insert = SelectionStepWrite(userID: UUID(), companyID: UUID(), draft: draft)
            let update = SelectionStepUpdate(draft: draft)
            XCTAssertEqual(insert.endsAt, timed ? draft.endDate : nil)
            XCTAssertEqual(update.endsAt, insert.endsAt)
            XCTAssertEqual(insert.endsOn, timed ? nil : LocalDate(date: draft.endDate))
            XCTAssertEqual(update.endsOn, insert.endsOn)
            let payload = try object(update)
            if timed {
                XCTAssertTrue(payload["ends_on"] is NSNull)
            } else {
                XCTAssertTrue(payload["ends_at"] is NSNull)
                let expected = try JSONDecoder().decode(String.self, from: JSONEncoder().encode(LocalDate(date: draft.endDate)))
                XCTAssertEqual(payload["ends_on"] as? String, expected)
            }
        }
        draft.hasEnd = false
        let cleared = try object(SelectionStepUpdate(draft: draft))
        XCTAssertTrue(cleared["ends_at"] is NSNull)
        XCTAssertTrue(cleared["ends_on"] is NSNull)
        draft.hasEnd = true
        draft.dateKind = .deadline
        let deadline = SelectionStepUpdate(draft: draft)
        XCTAssertNil(deadline.endsAt)
        XCTAssertNil(deadline.endsOn)
        XCTAssertEqual(deadline.deadlineAt, draft.date)
        XCTAssertNil(deadline.startsAt)
    }

    func testTimedMidnightExclusiveAndZeroDurationCoverage() {
        let range = step(end: date(2027, 1, 2, 0))
        XCTAssertTrue(range.covers(day: date(), calendar: calendar))
        XCTAssertTrue(range.covers(day: date(2027, 1, 1), calendar: calendar))
        XCTAssertFalse(range.covers(day: date(2027, 1, 2), calendar: calendar))
        XCTAssertFalse(range.covers(day: date(2026, 12, 30), calendar: calendar))
        let zero = step(end: date())
        XCTAssertTrue(zero.covers(day: date(), calendar: calendar))
        XCTAssertFalse(zero.isOngoing(relativeTo: date(), calendar: calendar))
        let sameDay = step(end: date(2026, 12, 31, 12))
        XCTAssertTrue(sameDay.isOngoing(relativeTo: date(2026, 12, 31, 11), calendar: calendar))
        XCTAssertFalse(sameDay.isOngoing(relativeTo: date(2026, 12, 31, 12), calendar: calendar))
    }

    func testDateOnlyInclusiveAcrossYearsAndTimeZones() {
        let range = step(timed: false, end: date(2027, 1, 2))
        for zone in ["Asia/Tokyo", "America/Los_Angeles"] {
            var local = calendar
            local.timeZone = TimeZone(identifier: zone)!
            let last = LocalDate(year: 2027, month: 1, day: 2).date(calendar: local)!
            XCTAssertTrue(range.covers(day: last, calendar: local))
            XCTAssertTrue(range.isOngoing(relativeTo: last.addingTimeInterval(23 * 3600), calendar: local))
            XCTAssertFalse(range.covers(day: local.date(byAdding: .day, value: 1, to: last)!, calendar: local))
        }
        let sameDay = step(timed: false, end: date())
        XCTAssertTrue(sameDay.covers(day: date(), calendar: calendar))
    }

    func testCalendarQueriesLongRangesWithoutExpandingDaysAndKeepsCompleted() {
        var range = step(end: date(9999, 12, 31))
        range.status = .completed
        let index = CalendarEventIndex(selectionSteps: [range], tasks: [], calendar: calendar)
        XCTAssertEqual(index.events(on: date(5000, 1, 1)).map(\.id), ["selection-\(range.id)-start"])
        range.status = .cancelled
        XCTAssertTrue(CalendarEventIndex(selectionSteps: [range], tasks: [], calendar: calendar).events(on: date()).isEmpty)
    }

    func testHomeRetainsOngoingRangeUntilEndWithoutCompletingIt() {
        let range = step(end: date(2027, 1, 2, 0))
        let ongoing = HomeSelectionBuckets.make(steps: [range], relativeTo: date(2027, 1, 1), calendar: calendar)
        XCTAssertEqual(ongoing.upcoming.map(\.id), [range.id])
        XCTAssertTrue(ongoing.past.isEmpty)
        let ended = HomeSelectionBuckets.make(steps: [range], relativeTo: date(2027, 1, 2, 0), calendar: calendar)
        XCTAssertTrue(ended.upcoming.isEmpty)
        XCTAssertEqual(ended.past.map(\.id), [range.id])
        XCTAssertEqual(range.status, .scheduled)
        XCTAssertNotNil(range.nextMilestone(relativeTo: date(2027, 1, 1)))
        let dateOnly = step(timed: false, end: date(2027, 1, 2))
        XCTAssertEqual(HomeSelectionBuckets.make(steps: [dateOnly], relativeTo: date(2027, 1, 2, 23), calendar: calendar).upcoming.count, 1)
    }

    func testFormattingIncludesBothDatesYearsAndStartOnlyLabel() {
        XCTAssertTrue(DateFormatting.schedule(step(), calendar: calendar).hasPrefix("開始 "))
        let same = DateFormatting.schedule(step(end: date(2026, 12, 31, 12)), calendar: calendar, referenceDate: date())
        XCTAssertTrue(same.contains("10:00〜12:00"))
        XCTAssertFalse(same.contains("2026年"))
        let crossing = DateFormatting.schedule(step(end: date(2027, 1, 1, 12)), calendar: calendar)
        XCTAssertTrue(crossing.contains("2026年12月31日"))
        XCTAssertTrue(crossing.contains("2027年1月1日"))
        let dateOnly = DateFormatting.schedule(step(timed: false, end: date(2027, 1, 1)), calendar: calendar)
        XCTAssertFalse(dateOnly.contains(":"))
        XCTAssertTrue(dateOnly.contains("〜"))
    }

    func testCompactCurrentNoncurrentAndCrossYearEndpointsRetainAccessibleYears() {
        let current = DateFormatting.scheduleText(step(end: date(2026, 12, 31, 12)), calendar: calendar, referenceDate: date())
        XCTAssertFalse(current.compact.contains("2026年"))
        XCTAssertEqual(current.end, "12:00")
        XCTAssertTrue(current.accessibilityLabel.contains("2026年"))
        let old = DateFormatting.scheduleText(step(end: date(2026, 12, 31, 12)), calendar: calendar, referenceDate: date(2028, 1, 1))
        XCTAssertEqual(old.compact.components(separatedBy: "2026年").count, 2)
        let crossing = DateFormatting.scheduleText(step(end: date(2027, 1, 1)), calendar: calendar, referenceDate: date())
        XCTAssertTrue(crossing.start.contains("2026年"))
        XCTAssertTrue(crossing.end?.contains("2027年") == true)
        var multiDay = step(timed: false, end: date(2026, 12, 31))
        multiDay.startsOn = LocalDate(year: 2026, month: 12, day: 30)
        let days = DateFormatting.scheduleText(multiDay, calendar: calendar, referenceDate: date())
        XCTAssertEqual(days.start, "予定 12月30日(水)")
        XCTAssertEqual(days.end, "12月31日(木)")
        XCTAssertFalse(days.compact.contains(":"))
        let noncurrent = DateFormatting.scheduleText(multiDay, calendar: calendar, referenceDate: date(2028, 1, 1))
        XCTAssertTrue(noncurrent.start.contains("2026年"))
        XCTAssertFalse(noncurrent.end?.contains("年") == true)
        let startOnly = DateFormatting.scheduleText(step(), calendar: calendar, referenceDate: date())
        XCTAssertTrue(startOnly.start.hasPrefix("開始 "))
        XCTAssertFalse(startOnly.start.contains("年"))
        XCTAssertNil(startOnly.end)
    }

    func testEndDoesNotCreateOrMoveNotifications() {
        let original = step()
        var range = original
        range.endsAt = date(2027, 1, 2)
        let now = date(2026, 12, 30)
        let before = NotificationPlanBuilder.make(steps: [original], tasks: [], companyNames: [:], now: now)
        let after = NotificationPlanBuilder.make(steps: [range], tasks: [], companyNames: [:], now: now)
        XCTAssertEqual(before, after)
        XCTAssertEqual(after.count, 1)
        XCTAssertTrue(NotificationPlanBuilder.make(steps: [range], tasks: [], companyNames: [:], now: date(2027, 1, 1)).isEmpty)
    }
}
