import Foundation

/// UI representation. Existing elapsed/calendar values retain their semantics;
/// months and date-only minute/hour offsets use a calendar-relative wire format.
struct RelativeNotificationTiming: Equatable {
    enum Unit: String, CaseIterable, Identifiable {
        case minutes, hours, days, weeks, months
        var id: String { rawValue }
        var title: String {
            switch self { case .minutes: return "分前"; case .hours: return "時間前"
            case .days: return "日前"; case .weeks: return "週間前"; case .months: return "か月前" }
        }
    }
    var value: Int
    var unit: Unit
    static func units(hasTime: Bool) -> [Unit] { Unit.allCases }
    init(value: Int = 1, unit: Unit = .days) { self.value = value; self.unit = unit }
    init?(custom: CustomNotificationTiming, hasTime: Bool) {
        guard custom.isValid(hasTime: hasTime) else { return nil }
        if custom.mode == .relative, let storedUnit = custom.unit,
           let unit = Unit(rawValue: storedUnit.rawValue) {
            self.init(value: custom.value, unit: unit)
            return
        }
        if hasTime {
            if custom.mode == .calendar, custom.value == 0 {
                self.init(value: 0, unit: .days)
                return
            }
            guard custom.mode == .elapsed, let oldUnit = custom.unit else { return nil }
            let minutes = custom.value * (oldUnit == .hours ? 60 : 1)
            if minutes.isMultiple(of: 10_080) { self.init(value: minutes / 10_080, unit: .weeks) }
            else if minutes.isMultiple(of: 1_440) { self.init(value: minutes / 1_440, unit: .days) }
            else { self.init(value: custom.value, unit: oldUnit == .hours ? .hours : .minutes) }
        } else {
            guard custom.mode == .calendar, custom.hour == 9, custom.minute == 0 else { return nil }
            self.init(value: custom.value, unit: custom.value > 0 && custom.value.isMultiple(of: 7) ? .weeks : .days)
            if unit == .weeks { value /= 7 }
        }
    }
    func maximum(hasTime: Bool) -> Int {
        switch unit { case .minutes: return hasTime ? 2_016_000 : 200; case .hours: return hasTime ? 33_600 : 200
        case .days: return 1_400; case .weeks: return 200; case .months: return 200 }
    }
    func minimum(hasTime: Bool) -> Int { unit == .days ? 0 : 1 }
    func supports(_ unit: Unit, hasTime: Bool) -> Bool {
        var candidate = self
        candidate.unit = unit
        return candidate.isSelectable(hasTime: hasTime)
    }
    func custom(hasTime: Bool) -> CustomNotificationTiming? {
        guard Self.units(hasTime: hasTime).contains(unit),
              (minimum(hasTime: hasTime)...maximum(hasTime: hasTime)).contains(value) else { return nil }
        if value == 0, unit == .days { return .calendar() }
        if unit == .months || (!hasTime && (unit == .minutes || unit == .hours)) {
            guard value <= 200, let storedUnit = CustomNotificationTiming.Unit(rawValue: unit.rawValue) else { return nil }
            return .relative(value, unit: storedUnit)
        }
        if !hasTime { return .calendar(daysBefore: value * (unit == .weeks ? 7 : 1)) }
        switch unit {
        case .minutes: return .elapsed(value)
        case .hours: return .elapsed(value, unit: .hours)
        case .days: return .elapsed(value * 24, unit: .hours)
        case .weeks: return .elapsed(value * 168, unit: .hours)
        case .months: return .relative(value, unit: .months)
        }
    }
    var usesNotificationClock: Bool { [.days, .weeks, .months].contains(unit) }

    func clockCustom(hour: Int = 9, minute: Int = 0) -> CustomNotificationTiming? {
        guard usesNotificationClock, isSelectable(hasTime: true),
              let storedUnit = CustomNotificationTiming.Unit(rawValue: unit.rawValue) else { return nil }
        if value == 0, unit == .days { return .calendar(hour: hour, minute: minute) }
        return .relative(value, unit: storedUnit).withNotificationClock(hour: hour, minute: minute)
    }

    var title: String { value == 0 && unit == .days ? "当日" : "\(value)\(unit.title)" }
    func wheelValues(hasTime: Bool) -> ClosedRange<Int> {
        minimum(hasTime: hasTime)...min(200, maximum(hasTime: hasTime))
    }
    func isSelectable(hasTime: Bool) -> Bool {
        Self.units(hasTime: hasTime).contains(unit) && wheelValues(hasTime: hasTime).contains(value)
    }
    /// Only an explicit Custom selection replaces an out-of-range stored value.
    static func initialSelection(
        current: Self?, remembered: Self?, hasTime: Bool
    ) -> Self {
        [current, remembered].compactMap { $0 }.first { $0.isSelectable(hasTime: hasTime) } ?? .init()
    }
}

/// Retain the chosen wheel representation during editing, even when its wire value
/// is equivalent to another unit or a preset. Separate instances isolate precision modes.
struct RelativeNotificationPresentation {
    private(set) var isCustom = false
    private var edited: RelativeNotificationTiming?

    mutating func edit(_ value: RelativeNotificationTiming) {
        isCustom = true
        edited = value
    }

    mutating func selectPreset() { isCustom = false }

    func value(custom: CustomNotificationTiming, hasTime: Bool) -> RelativeNotificationTiming? {
        if isCustom, let edited, edited.custom(hasTime: hasTime) == custom { return edited }
        return RelativeNotificationTiming(custom: custom, hasTime: hasTime)
    }
}

/// Menu entries follow the supplied timed/date-only reference screens.
struct ReminderMenuOption: Identifiable, Equatable {
    let id: String
    let timing: RelativeNotificationTiming
    var title: String { timing.title }
    static func options(hasTime: Bool) -> [Self] {
        let values: [(Int, RelativeNotificationTiming.Unit)] = hasTime
            ? [(0, .days), (5, .minutes), (15, .minutes), (30, .minutes), (1, .hours), (2, .hours),
               (1, .days), (2, .days), (1, .weeks), (1, .months)]
            : [(0, .days), (1, .days), (2, .days), (1, .weeks), (2, .weeks),
               (1, .months), (3, .months), (6, .months)]
        return values.map { Self(id: "reminder_\($0.0)_\($0.1.rawValue)", timing: .init(value: $0.0, unit: $0.1)) }
    }
}
