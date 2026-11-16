import XCTest
@testable import SwiftRecruitApp

final class CalendarEventIndexTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3_600)!
        return calendar
    }

    func testIncludesDateOnlySelectionAndTaskWithoutCompatibilityTimestamps() throws {
        let date = LocalDate(year: 2030, month: 1, day: 2)
        let step = makeStep(startsOn: date, deadlineOn: date)
        let task = makeTask(dueOn: date)
        let selectedDate = try XCTUnwrap(date.date(calendar: calendar))

        let events = CalendarEventIndex(
            selectionSteps: [step],
            tasks: [task],
            calendar: calendar
        ).events(on: selectedDate)

        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(Set(events.map(\.marker)), [.selection, .deadline, .task])
    }

    func testUsesDateOnlyValueInsteadOfCompatibilityTimestamp() throws {
        let localDate = LocalDate(year: 2030, month: 1, day: 2)
        let compatibilityDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2030, month: 1, day: 3, hour: 12))
        )
        var task = makeTask(dueOn: localDate)
        task.dueAt = compatibilityDate
        let expectedDate = try XCTUnwrap(localDate.date(calendar: calendar))

        let index = CalendarEventIndex(selectionSteps: [], tasks: [task], calendar: calendar)

        XCTAssertEqual(index.events(on: expectedDate).count, 1)
        XCTAssertTrue(index.events(on: compatibilityDate).isEmpty)
    }

    func testExcludesCancelledSelection() throws {
        let date = LocalDate(year: 2030, month: 1, day: 2)
        let selectedDate = try XCTUnwrap(date.date(calendar: calendar))

        let events = CalendarEventIndex(
            selectionSteps: [makeStep(startsOn: date, status: .cancelled)],
            tasks: [],
            calendar: calendar
        ).events(on: selectedDate)

        XCTAssertTrue(events.isEmpty)
    }

    func testMarksCompletedSelectionAndTaskAsCompleted() throws {
        let date = LocalDate(year: 2030, month: 1, day: 2)
        let selectedDate = try XCTUnwrap(date.date(calendar: calendar))
        let completedAt = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2030, month: 1, day: 1))
        )
        let step = makeStep(startsOn: date, status: .completed)
        var task = makeTask(dueOn: date)
        task.completedAt = completedAt

        let events = CalendarEventIndex(
            selectionSteps: [step],
            tasks: [task],
            calendar: calendar
        ).events(on: selectedDate)

        XCTAssertEqual(events.count, 2)
        XCTAssertTrue(events.allSatisfy(\.isCompleted))
        XCTAssertEqual(Set(events.map(\.marker)), [.completed])
    }

    func testBothMilestonesRemainDistinctAndReflectRestoredStatus() throws {
        let date = LocalDate(year: 2030, month: 1, day: 2)
        let day = try XCTUnwrap(date.date(calendar: calendar))
        var step = makeStep(startsOn: date, deadlineOn: date, status: .completed)
        let completed = CalendarEventIndex(selectionSteps: [step], tasks: [], calendar: calendar).events(on: day)
        XCTAssertEqual(completed.count, 2)
        XCTAssertEqual(Set(completed.map(\.id)).count, 2)
        XCTAssertTrue(completed.allSatisfy(\.isCompleted))
        step.status = .scheduled
        let restored = CalendarEventIndex(selectionSteps: [step], tasks: [], calendar: calendar).events(on: day)
        XCTAssertEqual(Set(restored.map(\.id)), Set(completed.map(\.id)))
        XCTAssertTrue(restored.allSatisfy { !$0.isCompleted })
        XCTAssertEqual(Set(restored.map(\.marker)), [.selection, .deadline])
    }

    func testSortsTimedEventsChronologically() throws {
        let morning = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2030, month: 1, day: 2, hour: 9))
        )
        let afternoon = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2030, month: 1, day: 2, hour: 15))
        )
        var earlyTask = makeTask(dueOn: nil)
        earlyTask.title = "午前"
        earlyTask.dueAt = morning
        earlyTask.dueHasTime = true
        var lateTask = makeTask(dueOn: nil)
        lateTask.title = "午後"
        lateTask.dueAt = afternoon
        lateTask.dueHasTime = true

        let events = CalendarEventIndex(
            selectionSteps: [],
            tasks: [lateTask, earlyTask],
            calendar: calendar
        ).events(on: morning)

        XCTAssertEqual(events.map(\.title), ["午前", "午後"])
    }

    private func makeStep(
        startsOn: LocalDate?,
        deadlineOn: LocalDate? = nil,
        status: SelectionStepStatus = .scheduled
    ) -> SelectionStep {
        SelectionStep(
            id: UUID(),
            userID: UUID(),
            companyID: UUID(),
            type: .interview,
            customTitle: nil,
            startsAt: nil,
            startsOn: startsOn,
            startsHasTime: false,
            deadlineAt: nil,
            deadlineOn: deadlineOn,
            deadlineHasTime: false,
            status: status,
            memo: nil,
            notificationEnabled: false,
            createdAt: .distantPast,
            updatedAt: .distantPast
        )
    }

    private func makeTask(dueOn: LocalDate?) -> RecruitTask {
        RecruitTask(
            id: UUID(),
            userID: UUID(),
            companyID: nil,
            title: "ToDo",
            memo: nil,
            dueAt: nil,
            dueOn: dueOn,
            dueHasTime: false,
            completedAt: nil,
            notificationEnabled: false,
            createdAt: .distantPast,
            updatedAt: .distantPast
        )
    }
}
