import Foundation

enum DateFormatting {
    static func yearFormat(for calendar: Calendar) -> String {
        calendar.identifier == .japanese ? "Gy年" : "yyyy年"
    }

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
        func formatter(_ pattern: String) -> DateFormatter {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "ja_JP")
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = pattern
            return formatter
        }
        let day = formatter("M月d日(E)")
        let year = formatter(yearFormat(for: calendar))
        let time = step.startsHasTime ? formatter("H:mm") : nil
        let startNeedsYear = !calendar.isDate(start, equalTo: referenceDate, toGranularity: .year)
        let crossesYear = end.map { !calendar.isDate($0, equalTo: start, toGranularity: .year) } ?? false
        func endpoint(_ date: Date) -> (short: String, full: String, clock: String?) {
            let clock = time?.string(from: date)
            let short = day.string(from: date) + (clock.map { " " + $0 } ?? "")
            return (short, year.string(from: date) + short, clock)
        }
        let prefix = end == nil ? "開始 " : "予定 "
        let first = endpoint(start)
        let startText = prefix + (crossesYear || startNeedsYear ? first.full : first.short)
        let fullStart = prefix + first.full
        guard let end else {
            return ScheduleText(start: startText, end: nil, accessibilityLabel: fullStart)
        }
        let last = endpoint(end)
        let endText = calendar.isDate(start, inSameDayAs: end) ? last.clock : (crossesYear ? last.full : last.short)
        return ScheduleText(start: startText, end: endText, accessibilityLabel: fullStart + "から" + last.full + "まで")
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
        let includesYear = !calendar.isDate(date, equalTo: referenceDate, toGranularity: .year)
        formatter.dateFormat = (includesYear ? yearFormat(for: calendar) + "M月d日(E)" : "M月d日(E)") + (hasTime ? " H:mm" : "")
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
