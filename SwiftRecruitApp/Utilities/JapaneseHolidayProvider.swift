import Foundation

struct JapaneseHolidayProvider: Sendable {
    func holidayName(on date: Date, calendar inputCalendar: Calendar = .current) -> String? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "ja_JP")
        calendar.timeZone = inputCalendar.timeZone
        let day = calendar.startOfDay(for: date)
        let year = calendar.component(.year, from: day)
        return holidays(in: year, calendar: calendar)[day]
    }

    func holidays(in year: Int, timeZone: TimeZone) -> [Date: String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "ja_JP")
        calendar.timeZone = timeZone
        return holidays(in: year, calendar: calendar)
    }

    private func holidays(in year: Int, calendar: Calendar) -> [Date: String] {
        // Job-hunting schedules are contemporary. This bounded range keeps the
        // statutory rules deterministic without pretending historical rules are current.
        guard (2000...2099).contains(year) else { return [:] }
        var values = fixedAndMovingHolidays(in: year, calendar: calendar)

        // A weekday between two national holidays is also a holiday.
        if let yearStart = makeDate(year: year, month: 1, day: 2, calendar: calendar),
           let yearEnd = makeDate(year: year, month: 12, day: 30, calendar: calendar) {
            var date = yearStart
            while date <= yearEnd {
                if values[date] == nil,
                   let previous = calendar.date(byAdding: .day, value: -1, to: date),
                   let next = calendar.date(byAdding: .day, value: 1, to: date),
                   values[calendar.startOfDay(for: previous)] != nil,
                   values[calendar.startOfDay(for: next)] != nil {
                    values[date] = "国民の休日"
                }
                guard let nextDate = calendar.date(byAdding: .day, value: 1, to: date) else { break }
                date = calendar.startOfDay(for: nextDate)
            }
        }

        // A Sunday holiday is observed on the next non-holiday.
        for holiday in values.keys.sorted() where calendar.component(.weekday, from: holiday) == 1 {
            guard var substitute = calendar.date(byAdding: .day, value: 1, to: holiday) else { continue }
            substitute = calendar.startOfDay(for: substitute)
            while values[substitute] != nil {
                guard let next = calendar.date(byAdding: .day, value: 1, to: substitute) else { break }
                substitute = calendar.startOfDay(for: next)
            }
            if calendar.component(.year, from: substitute) == year {
                values[substitute] = "振替休日"
            }
        }
        return values
    }

    private func fixedAndMovingHolidays(in year: Int, calendar: Calendar) -> [Date: String] {
        var values: [Date: String] = [:]
        add("元日", year, 1, 1, to: &values, calendar: calendar)
        addNthWeekday("成人の日", year, 1, weekday: 2, ordinal: 2, to: &values, calendar: calendar)
        add("建国記念の日", year, 2, 11, to: &values, calendar: calendar)
        if year >= 2020 { add("天皇誕生日", year, 2, 23, to: &values, calendar: calendar) }
        add("春分の日", year, 3, vernalEquinoxDay(year), to: &values, calendar: calendar)
        add("昭和の日", year, 4, 29, to: &values, calendar: calendar)
        add("憲法記念日", year, 5, 3, to: &values, calendar: calendar)
        add("みどりの日", year, 5, 4, to: &values, calendar: calendar)
        add("こどもの日", year, 5, 5, to: &values, calendar: calendar)

        if year == 2020 {
            add("海の日", year, 7, 23, to: &values, calendar: calendar)
            add("スポーツの日", year, 7, 24, to: &values, calendar: calendar)
            add("山の日", year, 8, 10, to: &values, calendar: calendar)
        } else if year == 2021 {
            add("海の日", year, 7, 22, to: &values, calendar: calendar)
            add("スポーツの日", year, 7, 23, to: &values, calendar: calendar)
            add("山の日", year, 8, 8, to: &values, calendar: calendar)
        } else {
            addNthWeekday("海の日", year, 7, weekday: 2, ordinal: 3, to: &values, calendar: calendar)
            add("山の日", year, 8, 11, to: &values, calendar: calendar)
            addNthWeekday("スポーツの日", year, 10, weekday: 2, ordinal: 2, to: &values, calendar: calendar)
        }

        addNthWeekday("敬老の日", year, 9, weekday: 2, ordinal: 3, to: &values, calendar: calendar)
        add("秋分の日", year, 9, autumnalEquinoxDay(year), to: &values, calendar: calendar)
        add("文化の日", year, 11, 3, to: &values, calendar: calendar)
        add("勤労感謝の日", year, 11, 23, to: &values, calendar: calendar)
        return values
    }

    private func add(
        _ name: String, _ year: Int, _ month: Int, _ day: Int,
        to values: inout [Date: String], calendar: Calendar
    ) {
        if let date = makeDate(year: year, month: month, day: day, calendar: calendar) {
            values[date] = name
        }
    }

    private func addNthWeekday(
        _ name: String, _ year: Int, _ month: Int, weekday: Int, ordinal: Int,
        to values: inout [Date: String], calendar: Calendar
    ) {
        guard let first = makeDate(year: year, month: month, day: 1, calendar: calendar) else { return }
        let offset = (weekday - calendar.component(.weekday, from: first) + 7) % 7
        add(name, year, month, 1 + offset + (ordinal - 1) * 7, to: &values, calendar: calendar)
    }

    private func makeDate(year: Int, month: Int, day: Int, calendar: Calendar) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day))
            .map { calendar.startOfDay(for: $0) }
    }

    private func vernalEquinoxDay(_ year: Int) -> Int {
        Int(floor(20.8431 + 0.242194 * Double(year - 1980) - floor(Double(year - 1980) / 4)))
    }

    private func autumnalEquinoxDay(_ year: Int) -> Int {
        Int(floor(23.2488 + 0.242194 * Double(year - 1980) - floor(Double(year - 1980) / 4)))
    }
}
