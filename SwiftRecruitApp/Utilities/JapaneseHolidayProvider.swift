import Foundation

struct JapaneseHolidayProvider: Sendable {
    func holidayName(on date: Date, calendar inputCalendar: Calendar = .current) -> String? {
        let calendar = gregorianCalendar(timeZone: inputCalendar.timeZone)
        let day = calendar.startOfDay(for: date)
        let year = calendar.component(.year, from: day)
        return holidays(in: year, calendar: calendar)[day]
    }

    func holidays(in year: Int, timeZone: TimeZone) -> [Date: String] {
        let calendar = gregorianCalendar(timeZone: timeZone)
        return holidays(in: year, calendar: calendar)
    }

    func holidays(containing dates: [Date], timeZone: TimeZone) -> [Date: String] {
        let calendar = gregorianCalendar(timeZone: timeZone)
        let years = Set(dates.map { calendar.component(.year, from: $0) })
        return years.reduce(into: [:]) { result, year in
            result.merge(holidays(in: year, calendar: calendar)) { current, _ in current }
        }
    }

    private func holidays(in year: Int, calendar: Calendar) -> [Date: String] {
        // Historical rules are implemented from 2000. Future dates follow the
        // current law and the equinox predictions published through 2050, so
        // this must be updated if the law or the published predictions change.
        guard (2000...2050).contains(year) else { return [:] }
        let nationalHolidays = nationalHolidays(in: year, calendar: calendar)
        var values = nationalHolidays

        // A weekday between two national holidays is also a holiday.
        if let yearStart = makeDate(year: year, month: 1, day: 2, calendar: calendar),
           let yearEnd = makeDate(year: year, month: 12, day: 30, calendar: calendar) {
            var date = yearStart
            while date <= yearEnd {
                if values[date] == nil,
                   (year >= 2007 || calendar.component(.weekday, from: date) != 1),
                   let previous = calendar.date(byAdding: .day, value: -1, to: date),
                   let next = calendar.date(byAdding: .day, value: 1, to: date),
                   nationalHolidays[calendar.startOfDay(for: previous)] != nil,
                   nationalHolidays[calendar.startOfDay(for: next)] != nil {
                    values[date] = "国民の休日"
                }
                guard let nextDate = calendar.date(byAdding: .day, value: 1, to: date) else { break }
                date = calendar.startOfDay(for: nextDate)
            }
        }

        // Since 2007, a Sunday holiday is observed on the next day that is not
        // itself a national holiday. Before then, only the following day applied.
        for holiday in nationalHolidays.keys.sorted()
        where calendar.component(.weekday, from: holiday) == 1 {
            guard var substitute = calendar.date(byAdding: .day, value: 1, to: holiday) else { continue }
            substitute = calendar.startOfDay(for: substitute)
            while year >= 2007, nationalHolidays[substitute] != nil {
                guard let next = calendar.date(byAdding: .day, value: 1, to: substitute) else { break }
                substitute = calendar.startOfDay(for: next)
            }
            if calendar.component(.year, from: substitute) == year,
               values[substitute] == nil {
                values[substitute] = "振替休日"
            }
        }
        return values
    }

    private func nationalHolidays(in year: Int, calendar: Calendar) -> [Date: String] {
        var values: [Date: String] = [:]
        add("元日", year, 1, 1, to: &values, calendar: calendar)
        addNthWeekday("成人の日", year, 1, weekday: 2, ordinal: 2, to: &values, calendar: calendar)
        add("建国記念の日", year, 2, 11, to: &values, calendar: calendar)
        if year >= 2020 {
            add("天皇誕生日", year, 2, 23, to: &values, calendar: calendar)
        } else if year <= 2018 {
            add("天皇誕生日", year, 12, 23, to: &values, calendar: calendar)
        }
        add("春分の日", year, 3, vernalEquinoxDay(year), to: &values, calendar: calendar)
        add(year >= 2007 ? "昭和の日" : "みどりの日", year, 4, 29, to: &values, calendar: calendar)
        add("憲法記念日", year, 5, 3, to: &values, calendar: calendar)
        if year >= 2007 {
            add("みどりの日", year, 5, 4, to: &values, calendar: calendar)
        }
        add("こどもの日", year, 5, 5, to: &values, calendar: calendar)

        if year == 2019 {
            add("天皇の即位の日", year, 5, 1, to: &values, calendar: calendar)
            add("即位礼正殿の儀の行われる日", year, 10, 22, to: &values, calendar: calendar)
        }

        if year <= 2002 {
            add("海の日", year, 7, 20, to: &values, calendar: calendar)
        } else if year == 2020 {
            add("海の日", year, 7, 23, to: &values, calendar: calendar)
        } else if year == 2021 {
            add("海の日", year, 7, 22, to: &values, calendar: calendar)
        } else {
            addNthWeekday("海の日", year, 7, weekday: 2, ordinal: 3, to: &values, calendar: calendar)
        }

        if year == 2020 {
            add("山の日", year, 8, 10, to: &values, calendar: calendar)
        } else if year == 2021 {
            add("山の日", year, 8, 8, to: &values, calendar: calendar)
        } else if year >= 2016 {
            add("山の日", year, 8, 11, to: &values, calendar: calendar)
        }

        if year == 2020 {
            add("スポーツの日", year, 7, 24, to: &values, calendar: calendar)
        } else if year == 2021 {
            add("スポーツの日", year, 7, 23, to: &values, calendar: calendar)
        } else {
            addNthWeekday(
                year >= 2020 ? "スポーツの日" : "体育の日",
                year,
                10,
                weekday: 2,
                ordinal: 2,
                to: &values,
                calendar: calendar
            )
        }

        if year <= 2002 {
            add("敬老の日", year, 9, 15, to: &values, calendar: calendar)
        } else {
            addNthWeekday("敬老の日", year, 9, weekday: 2, ordinal: 3, to: &values, calendar: calendar)
        }

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

    private func gregorianCalendar(timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "ja_JP")
        calendar.timeZone = timeZone
        return calendar
    }

    private func vernalEquinoxDay(_ year: Int) -> Int {
        Int(floor(20.8431 + 0.242194 * Double(year - 1980) - floor(Double(year - 1980) / 4)))
    }

    private func autumnalEquinoxDay(_ year: Int) -> Int {
        Int(floor(23.2488 + 0.242194 * Double(year - 1980) - floor(Double(year - 1980) / 4)))
    }
}

/// Keeps the holiday tables needed by the visible grid, including adjacent years.
@MainActor
final class VisibleHolidayCalendar {
    private let provider = JapaneseHolidayProvider()
    private var timeZone: TimeZone?
    private var years: Set<Int> = []
    private var names: [Date: String] = [:]

    func holidays(containing dates: [Date], timeZone: TimeZone) -> [Date: String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let visibleYears = Set(dates.map { calendar.component(.year, from: $0) })
        if self.timeZone != timeZone || visibleYears != years {
            names = provider.holidays(containing: dates, timeZone: timeZone)
            self.timeZone = timeZone
            years = visibleYears
        }
        return names
    }
}
