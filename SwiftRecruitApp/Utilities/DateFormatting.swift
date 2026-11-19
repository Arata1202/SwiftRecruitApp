import Foundation

enum DateFormatting {
    struct ScheduleText {
        let start: String
        let end: String?
        let accessibilityLabel: String

        var compact: String { start + (end.map { "〜" + $0 } ?? "") }
    }

    static func schedule(_ step: SelectionStep, calendar: Calendar = .current, referenceDate: Date = Date()) -> String {
        scheduleText(step, calendar: calendar, referenceDate: referenceDate).compact
    }

    /// Endpoints stay separate so narrow views can wrap at the range boundary first.
    static func scheduleText(_ step: SelectionStep, calendar: Calendar = .current, referenceDate: Date = Date()) -> ScheduleText {
        guard let start = step.startDate(calendar: calendar) else {
            return ScheduleText(start: "日程未設定", end: nil, accessibilityLabel: "日程未設定")
        }
        let end = step.endDate(calendar: calendar)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        let currentYear = calendar.component(.year, from: referenceDate)
        let startYear = calendar.component(.year, from: start)
        let crossesYear = end.map { calendar.component(.year, from: $0) != startYear } ?? false
        func dateText(_ date: Date, includeYear: Bool) -> String {
            formatter.dateFormat = includeYear ? "yyyy年M月d日(E)" : "M月d日(E)"
            let day = formatter.string(from: date)
            formatter.dateFormat = "H:mm"
            return step.startsHasTime ? day + " " + formatter.string(from: date) : day
        }
        let prefix = end == nil ? "開始 " : "予定 "
        let startText = prefix + dateText(start, includeYear: crossesYear || startYear != currentYear)
        let fullStart = prefix + dateText(start, includeYear: true)
        guard let end else {
            return ScheduleText(start: startText, end: nil, accessibilityLabel: fullStart)
        }
        let fullEnd = dateText(end, includeYear: true)
        let accessible = fullStart + "から" + fullEnd + "まで"
        if calendar.isDate(start, inSameDayAs: end) {
            formatter.dateFormat = "H:mm"
            return ScheduleText(start: startText, end: step.startsHasTime ? formatter.string(from: end) : nil, accessibilityLabel: accessible)
        }
        // In a noncurrent single year, the start establishes the year for both dates.
        let endText = dateText(end, includeYear: crossesYear)
        return ScheduleText(start: startText, end: endText, accessibilityLabel: accessible)
    }

    /// Compact list dates include the year only when it differs from the reference date.
    static func listDate(
        _ date: Date,
        hasTime: Bool,
        calendar: Calendar = .current,
        referenceDate: Date = Date()
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        let includesYear = calendar.component(.year, from: date) != calendar.component(.year, from: referenceDate)
        formatter.dateFormat = (includesYear ? "yyyy年M月d日(E)" : "M月d日(E)") + (hasTime ? " H:mm" : "")
        return formatter.string(from: date)
    }

    static func calendarMetadata(kind: String, date: Date, hasTime: Bool) -> String {
        hasTime ? "\(kind) \(time.string(from: date))" : "\(kind) 時刻未設定"
    }

    static func companyInformationDate(
        _ item: CompanyInformationItem,
        calendar: Calendar = .current,
        referenceDate: Date = Date()
    ) -> String? {
        guard let date = item.occurredOn, let instant = date.date(calendar: calendar) else { return nil }
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.calendar = gregorian
        formatter.timeZone = calendar.timeZone
        let includesYear = date.year != gregorian.component(.year, from: referenceDate)
        formatter.dateFormat = includesYear ? "yyyy年M月d日(E)" : "M月d日(E)"
        let label = item.category == .interview ? "面接日" : "記録日"
        return label + " " + formatter.string(from: instant)
    }

    static func localDateWithYear(_ date: LocalDate) -> String {
        "\(date.year)年\(date.month)月\(date.day)日"
    }

    static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M月d日(E)"
        return formatter
    }()

    static let dateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M月d日(E) H:mm"
        return formatter
    }()

    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "H:mm"
        return formatter
    }()
}
