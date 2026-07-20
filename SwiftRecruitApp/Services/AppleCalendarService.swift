import EventKit
import Foundation

struct AppleCalendarEventDescriptor: Sendable {
    let key: String
    let title: String
    let notes: String?
    let startDate: Date
    let hasTime: Bool

    var endDate: Date {
        let calendar = Calendar.current
        if hasTime {
            return calendar.date(byAdding: .hour, value: 1, to: startDate)
                ?? startDate.addingTimeInterval(3_600)
        }
        return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: startDate))
            ?? startDate.addingTimeInterval(86_400)
    }
}

enum AppleCalendarError: LocalizedError {
    case accessDenied
    case calendarUnavailable

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Appleカレンダーへのアクセスが許可されていません。iOSの設定からフルアクセスを許可してください。"
        case .calendarUnavailable:
            return "書き込み可能なAppleカレンダーが見つかりません。"
        }
    }
}

enum AppleCalendarSyncCategory: String, CaseIterable, Identifiable, Sendable {
    case selection
    case deadline
    case task

    var id: Self { self }

    var title: String {
        switch self {
        case .selection: "選考予定"
        case .deadline: "選考締切"
        case .task: "ToDo"
        }
    }
}

@MainActor
final class AppleCalendarService {
    private struct Record: Codable {
        var eventIdentifier: String
        var lastStartDate: Date
    }

    private let eventStore = EKEventStore()
    private let defaults: UserDefaults
    private let recordsKey = "appleCalendarExportRecords.v1"
    private let autoSyncKey = "appleCalendarAutoSyncEnabled.v1"
    private let suppressedKeysKey = "appleCalendarAutoSyncSuppressedKeys.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func isExported(key: String) -> Bool {
        guard let record = records[key] else { return false }
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return true }
        guard findEvent(key: key, record: record) == nil else { return true }
        var updated = records
        updated.removeValue(forKey: key)
        records = updated
        return false
    }

    func isAutoSyncSuppressed(key: String) -> Bool {
        suppressedKeys.contains(key)
    }

    var isAutoSyncEnabled: Bool {
        defaults.bool(forKey: autoSyncKey)
    }

    var hasManagedEvents: Bool {
        records.isEmpty == false
    }

    func isCategoryEnabled(_ category: AppleCalendarSyncCategory) -> Bool {
        if defaults.object(forKey: categoryKey(category)) == nil {
            return category == .selection
        }
        return defaults.bool(forKey: categoryKey(category))
    }

    func setCategory(_ category: AppleCalendarSyncCategory, enabled: Bool) {
        defaults.set(enabled, forKey: categoryKey(category))
    }

    func setAutoSyncEnabled(_ enabled: Bool) async throws {
        if enabled { try await ensureFullAccess(promptIfNeeded: true) }
        defaults.set(enabled, forKey: autoSyncKey)
    }

    @discardableResult
    func export(_ descriptor: AppleCalendarEventDescriptor) async throws -> Bool {
        try await ensureFullAccess(promptIfNeeded: true)
        var updatedSuppressedKeys = suppressedKeys
        updatedSuppressedKeys.remove(descriptor.key)
        suppressedKeys = updatedSuppressedKeys
        let existed = records[descriptor.key] != nil
        try upsert(descriptor)
        return existed == false
    }

    func sync(_ descriptor: AppleCalendarEventDescriptor) async throws {
        guard records[descriptor.key] != nil else { return }
        try await ensureFullAccess(promptIfNeeded: false)
        try upsert(descriptor)
    }

    func remove(key: String, suppressAutoSync: Bool = false) async throws {
        guard let record = records[key] else { return }
        try await ensureFullAccess(promptIfNeeded: false)
        if let event = findEvent(key: key, record: record) {
            try eventStore.remove(event, span: .thisEvent, commit: true)
        }
        var updated = records
        updated.removeValue(forKey: key)
        records = updated
        if suppressAutoSync {
            var updatedSuppressedKeys = suppressedKeys
            updatedSuppressedKeys.insert(key)
            suppressedKeys = updatedSuppressedKeys
        }
    }

    func removeSelection(id: UUID) async throws {
        try await remove(key: Self.selectionKey(id: id, kind: .start))
        try await remove(key: Self.selectionKey(id: id, kind: .deadline))
    }

    nonisolated static func selectionKey(id: UUID, kind: SelectionMilestoneKind) -> String {
        "selection-\(id.uuidString)-\(kind == .start ? "start" : "deadline")"
    }

    nonisolated static func taskKey(id: UUID) -> String {
        "task-\(id.uuidString)"
    }

    private func ensureFullAccess(promptIfNeeded: Bool) async throws {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            return
        case .notDetermined where promptIfNeeded:
            guard try await eventStore.requestFullAccessToEvents() else {
                throw AppleCalendarError.accessDenied
            }
        default:
            throw AppleCalendarError.accessDenied
        }
    }

    private func upsert(_ descriptor: AppleCalendarEventDescriptor) throws {
        var updatedRecords = records
        let existingRecord = updatedRecords[descriptor.key]
        let event = existingRecord.flatMap { findEvent(key: descriptor.key, record: $0) }
            ?? EKEvent(eventStore: eventStore)

        guard let calendar = event.calendar ?? eventStore.defaultCalendarForNewEvents,
              calendar.allowsContentModifications else {
            throw AppleCalendarError.calendarUnavailable
        }

        event.calendar = calendar
        event.title = descriptor.title
        event.startDate = descriptor.hasTime
            ? descriptor.startDate
            : Calendar.current.startOfDay(for: descriptor.startDate)
        event.endDate = descriptor.endDate
        event.isAllDay = descriptor.hasTime == false
        event.notes = [descriptor.notes, marker(for: descriptor.key)]
            .compactMap { $0 }
            .joined(separator: "\n\n")

        try eventStore.save(event, span: .thisEvent, commit: true)
        updatedRecords[descriptor.key] = Record(
            eventIdentifier: event.eventIdentifier,
            lastStartDate: event.startDate
        )
        records = updatedRecords
    }

    private func findEvent(key: String, record: Record) -> EKEvent? {
        if let event = eventStore.event(withIdentifier: record.eventIdentifier) {
            return event
        }

        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -2, to: record.lastStartDate) ?? record.lastStartDate
        let end = calendar.date(byAdding: .day, value: 2, to: record.lastStartDate) ?? record.lastStartDate
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        return eventStore.events(matching: predicate).first { $0.notes?.contains(marker(for: key)) == true }
    }

    private func marker(for key: String) -> String {
        "Rikuvision-ID: \(key)"
    }

    private func categoryKey(_ category: AppleCalendarSyncCategory) -> String {
        "appleCalendarAutoSyncCategory.v1.\(category.rawValue)"
    }

    private var records: [String: Record] {
        get {
            guard let data = defaults.data(forKey: recordsKey) else { return [:] }
            return (try? JSONDecoder().decode([String: Record].self, from: data)) ?? [:]
        }
        set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: recordsKey)
        }
    }

    private var suppressedKeys: Set<String> {
        get {
            Set(defaults.stringArray(forKey: suppressedKeysKey) ?? [])
        }
        set {
            defaults.set(Array(newValue).sorted(), forKey: suppressedKeysKey)
        }
    }
}
