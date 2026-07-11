#if DEBUG
import Foundation

enum ScreenshotData {
    static let userID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    static func make(
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> (companies: [Company], selectionSteps: [SelectionStep], tasks: [RecruitTask]) {
        let today = calendar.startOfDay(for: now)
        let createdAt = calendar.date(byAdding: .day, value: -14, to: today) ?? today

        let northstarID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let blueleafID = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
        let miraiID = UUID(uuidString: "10000000-0000-0000-0000-000000000003")!
        let harborID = UUID(uuidString: "10000000-0000-0000-0000-000000000004")!

        let companies = [
            Company(id: northstarID, userID: userID, name: "ノーススター株式会社", priority: 3, status: .active, url: "https://example.com", memo: "プロダクト開発と組織文化を確認", createdAt: createdAt, updatedAt: now),
            Company(id: blueleafID, userID: userID, name: "ブルーリーフ株式会社", priority: 3, status: .offer, url: nil, memo: nil, createdAt: createdAt, updatedAt: now),
            Company(id: miraiID, userID: userID, name: "株式会社ミライワークス", priority: 3, status: .considering, url: nil, memo: nil, createdAt: createdAt, updatedAt: now),
            Company(id: harborID, userID: userID, name: "ハーバーテック株式会社", priority: 3, status: .active, url: nil, memo: nil, createdAt: createdAt, updatedAt: now),
        ]

        let interviewDate = date(on: today, addingDays: 1, hour: 14, calendar: calendar)
        let documentDeadline = date(on: today, addingDays: 2, hour: 18, calendar: calendar)
        let briefingDate = date(on: today, addingDays: 4, hour: 11, calendar: calendar)
        let offerDate = date(on: today, addingDays: -2, hour: 15, calendar: calendar)

        let selectionSteps = [
            SelectionStep(id: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!, userID: userID, companyID: northstarID, type: .interview, customTitle: nil, startsAt: interviewDate, startsHasTime: true, deadlineAt: nil, deadlineHasTime: false, status: .scheduled, memo: "オンライン面接", notificationEnabled: true, createdAt: createdAt, updatedAt: now),
            SelectionStep(id: UUID(uuidString: "20000000-0000-0000-0000-000000000002")!, userID: userID, companyID: harborID, type: .document, customTitle: nil, startsAt: nil, startsHasTime: false, deadlineAt: documentDeadline, deadlineHasTime: true, status: .scheduled, memo: nil, notificationEnabled: true, createdAt: createdAt, updatedAt: now),
            SelectionStep(id: UUID(uuidString: "20000000-0000-0000-0000-000000000003")!, userID: userID, companyID: miraiID, type: .briefing, customTitle: nil, startsAt: briefingDate, startsHasTime: true, deadlineAt: nil, deadlineHasTime: false, status: .scheduled, memo: nil, notificationEnabled: true, createdAt: createdAt, updatedAt: now),
            SelectionStep(id: UUID(uuidString: "20000000-0000-0000-0000-000000000004")!, userID: userID, companyID: blueleafID, type: .offer, customTitle: nil, startsAt: offerDate, startsHasTime: true, deadlineAt: nil, deadlineHasTime: false, status: .completed, memo: nil, notificationEnabled: false, createdAt: createdAt, updatedAt: now),
        ]

        let tasks = [
            task(id: 1, companyID: northstarID, title: "面接で聞きたいことを整理", dueAt: now.addingTimeInterval(2 * 60 * 60), hasTime: true, createdAt: createdAt, updatedAt: now),
            task(id: 2, companyID: harborID, title: "エントリーシートを提出", dueAt: date(on: today, addingDays: 2, hour: 18, calendar: calendar), hasTime: true, createdAt: createdAt, updatedAt: now),
            task(id: 3, companyID: miraiID, title: "説明会の質問を準備", dueAt: date(on: today, addingDays: 4, hour: 9, calendar: calendar), hasTime: false, createdAt: createdAt, updatedAt: now),
            task(id: 4, companyID: nil, title: "証明写真を更新", dueAt: date(on: today, addingDays: 6, hour: 9, calendar: calendar), hasTime: false, createdAt: createdAt, updatedAt: now),
        ]

        return (companies, selectionSteps, tasks)
    }

    private static func date(
        on today: Date,
        addingDays days: Int,
        hour: Int,
        calendar: Calendar
    ) -> Date {
        let day = calendar.date(byAdding: .day, value: days, to: today) ?? today
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
    }

    private static func task(
        id: Int,
        companyID: UUID?,
        title: String,
        dueAt: Date,
        hasTime: Bool,
        createdAt: Date,
        updatedAt: Date
    ) -> RecruitTask {
        RecruitTask(
            id: UUID(uuidString: String(format: "30000000-0000-0000-0000-%012d", id))!,
            userID: userID,
            companyID: companyID,
            title: title,
            memo: nil,
            dueAt: dueAt,
            dueHasTime: hasTime,
            completedAt: nil,
            notificationEnabled: false,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
#endif
