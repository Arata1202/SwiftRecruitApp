import Foundation

enum DateFormatting {
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
