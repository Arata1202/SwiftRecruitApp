import Foundation

/// A local number-entry transaction. Opening, typing and cancelling never write to the task draft.
struct NotificationNumberSelection {
    enum Kind: CaseIterable {
        case minutes, hours, days

        init(custom: CustomNotificationTiming) {
            self = custom.mode == .calendar ? .days : custom.unit == .hours ? .hours : .minutes
        }

        var suffix: String {
            switch self {
            case .minutes: return "分前"
            case .hours: return "時間前"
            case .days: return "日前"
            }
        }

        var range: ClosedRange<Int> {
            switch self {
            case .minutes: return 1...525_600
            case .hours: return 1...8_760
            case .days: return 0...365
            }
        }

        var suggestions: [Int] {
            switch self {
            case .minutes: return [5, 10, 15, 30, 45, 60, 90, 120]
            case .hours: return [1, 2, 3, 6, 12, 24, 48, 72]
            case .days: return [0, 1, 2, 3, 7, 14, 30]
            }
        }

        var inputHint: String {
            switch self {
            case .minutes: return "1〜525,600分前で入力してください。"
            case .hours: return "1〜8,760時間前で入力してください。"
            case .days: return "0〜365日前で入力してください。"
            }
        }

        func choices(including current: Int) -> [Int] {
            Array(Set(suggestions + [current])).sorted()
        }
    }

    let kind: Kind
    let originalValue: Int
    var text: String

    init(kind: Kind, value: Int) {
        self.kind = kind
        originalValue = value
        text = value >= 0 ? String(value) : ""
    }

    var confirmedValue: Int? {
        guard let value = CustomNotificationTiming.parsedInput(text), kind.range.contains(value) else { return nil }
        return value
    }

    var validationMessage: String? {
        confirmedValue == nil ? kind.inputHint : nil
    }

    var hasChanges: Bool { text != (originalValue >= 0 ? String(originalValue) : "") }
}
