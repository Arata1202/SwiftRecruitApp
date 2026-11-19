import Foundation

/// UI-only representation. Timed days/weeks are exact 24-hour/168-hour intervals;
/// date-only days use the existing local-calendar 09:00 rule. Wire values stay unchanged.
struct RelativeNotificationTiming: Equatable {
    enum Unit: String, CaseIterable, Identifiable {
        case minutes, hours, days, weeks
        var id: String { rawValue }
        var title: String {
            switch self { case .minutes: return "分前"; case .hours: return "時間前"
            case .days: return "日前"; case .weeks: return "週間前" }
        }
    }
    var value: Int
    var unit: Unit
    static func units(hasTime: Bool) -> [Unit] { hasTime ? Unit.allCases : [.days, .weeks] }
    init(value: Int = 1, unit: Unit = .days) { self.value = value; self.unit = unit }
    init?(custom: CustomNotificationTiming, hasTime: Bool) {
        guard custom.isValid(hasTime: hasTime) else { return nil }
        if hasTime {
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
        switch unit { case .minutes: return 525_600; case .hours: return 8_760
        case .days: return 365; case .weeks: return 52 }
    }
    func minimum(hasTime: Bool) -> Int { !hasTime && unit == .days ? 0 : 1 }
    func supports(_ unit: Unit, hasTime: Bool) -> Bool {
        var candidate = self
        candidate.unit = unit
        return candidate.custom(hasTime: hasTime) != nil
    }
    func custom(hasTime: Bool) -> CustomNotificationTiming? {
        guard Self.units(hasTime: hasTime).contains(unit),
              (minimum(hasTime: hasTime)...maximum(hasTime: hasTime)).contains(value) else { return nil }
        if !hasTime { return .calendar(daysBefore: value * (unit == .weeks ? 7 : 1)) }
        switch unit {
        case .minutes: return .elapsed(value)
        case .hours: return .elapsed(value, unit: .hours)
        case .days: return .elapsed(value * 24, unit: .hours)
        case .weeks: return .elapsed(value * 168, unit: .hours)
        }
    }
    var title: String { value == 0 && unit == .days ? "当日" : "\(value)\(unit.title)" }
    func wheelValues(hasTime: Bool) -> [Int] {
        let upper = min(maximum(hasTime: hasTime), unit == .minutes ? 120 : unit == .hours ? 48 : 365)
        return Array(Set(Array(minimum(hasTime: hasTime)...upper) + [value])).sorted()
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
        if let edited, edited.custom(hasTime: hasTime) == custom { return edited }
        return RelativeNotificationTiming(custom: custom, hasTime: hasTime)
    }
}
