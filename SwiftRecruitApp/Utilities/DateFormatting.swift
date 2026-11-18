import Foundation

enum DateFormatting {
    /// One representation shared by lists, details and every covered calendar day.
    static func schedule(_ step: SelectionStep, calendar: Calendar = .current) -> String {
        guard let start = step.startDate(calendar: calendar) else { return "日程未設定" }
        let end = step.endDate(calendar: calendar)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        // Keep years explicit so old/future appointments and year crossings are unambiguous.
        formatter.dateFormat = "yyyy年M月d日(E)"
        let startDay = formatter.string(from: start)
        let endDay = end.map { formatter.string(from: $0) }
        formatter.dateFormat = "H:mm"
        let startText = step.startsHasTime ? "\(startDay) \(formatter.string(from: start))" : startDay
        guard let end, let endDay else { return "開始 \(startText)" }
        if calendar.isDate(start, inSameDayAs: end) {
            return step.startsHasTime
                ? "予定 \(startText)〜\(formatter.string(from: end))"
                : "予定 \(startDay)"
        }
        let endText = step.startsHasTime ? "\(endDay) \(formatter.string(from: end))" : endDay
        return "予定 \(startText)〜\(endText)"
    }

    static func calendarMetadata(kind: String, date: Date, hasTime: Bool) -> String {
        hasTime ? "\(kind) \(time.string(from: date))" : "\(kind) 時刻未設定"
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
