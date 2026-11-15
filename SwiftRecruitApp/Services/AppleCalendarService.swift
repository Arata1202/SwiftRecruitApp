import EventKit
import Foundation

struct AppleCalendarEventDescriptor: Sendable {
    let key: String
    let title: String
    let notes: String?
    let startDate: Date
    let hasTime: Bool
    let duration: TimeInterval

    var endDate: Date {
        let calendar = Calendar.current
        if hasTime {
            return startDate.addingTimeInterval(duration)
        }
        return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: startDate))
            ?? startDate.addingTimeInterval(86_400)
    }
}

struct AppleCalendarSavedEvent: Sendable {
    let identifier: String
    let startDate: Date
}

@MainActor
protocol AppleCalendarEventClient: AnyObject {
    var hasFullAccess: Bool { get }
    func requestFullAccess() async throws -> Bool
    func contains(identifier: String, lastStartDate: Date, key: String) -> Bool
    func save(
        _ descriptor: AppleCalendarEventDescriptor,
        existingIdentifier: String?,
        lastStartDate: Date?
    ) throws -> AppleCalendarSavedEvent
    func remove(identifier: String?, lastStartDate: Date, key: String) throws
}

@MainActor
final class EventKitCalendarEventClient: AppleCalendarEventClient {
    private let eventStore = EKEventStore()

    var hasFullAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    func requestFullAccess() async throws -> Bool {
        try await eventStore.requestFullAccessToEvents()
    }

    func contains(identifier: String, lastStartDate: Date, key: String) -> Bool {
        findEvent(identifier: identifier, lastStartDate: lastStartDate, key: key) != nil
    }

    func save(
        _ descriptor: AppleCalendarEventDescriptor,
        existingIdentifier: String?,
        lastStartDate: Date?
    ) throws -> AppleCalendarSavedEvent {
        let existingEvents = findEvents(
            identifier: existingIdentifier,
            lastStartDate: lastStartDate ?? descriptor.startDate,
            key: descriptor.key
        )
        let event = existingEvents.first ?? EKEvent(eventStore: eventStore)
        guard let calendar = event.calendar ?? eventStore.defaultCalendarForNewEvents,
              calendar.allowsContentModifications else {
            throw AppleCalendarError.calendarUnavailable
        }
        event.calendar = calendar
        event.title = descriptor.title
        event.startDate = descriptor.hasTime ? descriptor.startDate : Calendar.current.startOfDay(for: descriptor.startDate)
        event.endDate = descriptor.endDate
        event.isAllDay = descriptor.hasTime == false
        event.notes = [descriptor.notes, marker(for: descriptor.key)].compactMap { $0 }.joined(separator: "\n\n")
        try eventStore.save(event, span: .thisEvent, commit: false)
        for duplicate in existingEvents.dropFirst() {
            try eventStore.remove(duplicate, span: .thisEvent, commit: false)
        }
        try eventStore.commit()
        return AppleCalendarSavedEvent(identifier: event.eventIdentifier, startDate: event.startDate)
    }

    func remove(identifier: String?, lastStartDate: Date, key: String) throws {
        let events = findEvents(
            identifier: identifier,
            lastStartDate: lastStartDate,
            key: key
        )
        for event in events {
            try eventStore.remove(event, span: .thisEvent, commit: false)
        }
        if events.isEmpty == false {
            try eventStore.commit()
        }
    }

    private func findEvent(identifier: String, lastStartDate: Date, key: String) -> EKEvent? {
        findEvents(
            identifier: identifier,
            lastStartDate: lastStartDate,
            key: key
        ).first
    }

    private func findEvents(
        identifier: String?,
        lastStartDate: Date,
        key: String
    ) -> [EKEvent] {
        var matches: [EKEvent] = []
        if let identifier,
           let event = eventStore.event(withIdentifier: identifier) {
            matches.append(event)
        }

        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -2, to: lastStartDate) ?? lastStartDate
        let end = calendar.date(byAdding: .day, value: 2, to: lastStartDate) ?? lastStartDate
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        let markedEvents = eventStore.events(matching: predicate).filter {
            $0.notes?
                .components(separatedBy: .newlines)
                .contains(marker(for: key)) == true
        }
        for event in markedEvents where matches.contains(where: { isSameEvent($0, event) }) == false {
            matches.append(event)
        }
        return matches
    }

    private func isSameEvent(_ lhs: EKEvent, _ rhs: EKEvent) -> Bool {
        if let lhsIdentifier = lhs.eventIdentifier,
           let rhsIdentifier = rhs.eventIdentifier {
            return lhsIdentifier == rhsIdentifier
        }
        return lhs === rhs
    }

    private func marker(for key: String) -> String { "Rikuvision-ID: \(key)" }
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

enum AppleCalendarSyncPolicy {
    static func isUpcoming(
        date: Date,
        hasTime: Bool,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        hasTime
            ? date >= now
            : calendar.startOfDay(for: date) >= calendar.startOfDay(for: now)
    }
}

@MainActor
final class AppleCalendarService {
    private struct Record: Codable {
        var eventIdentifier: String
        var lastStartDate: Date
        var automatically: Bool
    }

    private struct LegacyRecord: Codable {
        var eventIdentifier: String
        var lastStartDate: Date
    }

    private let client: any AppleCalendarEventClient
    private let defaults: UserDefaults
    private var activeUserID: UUID?

    convenience init(defaults: UserDefaults = .standard) {
        self.init(defaults: defaults, client: EventKitCalendarEventClient())
    }

    init(defaults: UserDefaults, client: any AppleCalendarEventClient) {
        self.defaults = defaults
        self.client = client
    }

    func activate(userID: UUID?) {
        activeUserID = userID
        if userID != nil {
            migrateLegacyPreferencesIfNeeded()
            initializeSelectionPreferenceIfNeeded()
        }
    }

    func isExported(key: String) -> Bool {
        guard let record = records[key] else { return false }
        guard client.hasFullAccess else { return true }
        guard client.contains(
            identifier: record.eventIdentifier,
            lastStartDate: record.lastStartDate,
            key: key
        ) == false else { return true }
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

    var managedKeys: Set<String> {
        Set(records.keys)
    }

    func isCategoryEnabled(_ category: AppleCalendarSyncCategory) -> Bool {
        defaults.bool(forKey: categoryKey(category))
    }

    func setCategory(_ category: AppleCalendarSyncCategory, enabled: Bool) {
        defaults.set(enabled, forKey: categoryKey(category))
    }

    func setAutoSyncEnabled(_ enabled: Bool) async throws {
        if enabled { try await ensureFullAccess(promptIfNeeded: true) }
        defaults.set(enabled, forKey: autoSyncKey)
    }

    @discardableResult
    func export(
        _ descriptor: AppleCalendarEventDescriptor,
        automatically: Bool = false
    ) async throws -> Bool {
        try await ensureFullAccess(promptIfNeeded: true)
        var updatedSuppressedKeys = suppressedKeys
        updatedSuppressedKeys.remove(descriptor.key)
        suppressedKeys = updatedSuppressedKeys
        let existed = records[descriptor.key] != nil
        try upsert(descriptor, automatically: automatically)
        return existed == false
    }

    func sync(_ descriptor: AppleCalendarEventDescriptor) async throws {
        guard records[descriptor.key] != nil else { return }
        try await ensureFullAccess(promptIfNeeded: false)
        try upsert(descriptor, automatically: records[descriptor.key]?.automatically == true)
    }

    func remove(key: String, suppressAutoSync: Bool = false) async throws {
        guard let record = records[key] else {
            var updatedPendingKeys = pendingRemovalKeys
            updatedPendingKeys.remove(key)
            pendingRemovalKeys = updatedPendingKeys
            return
        }
        var updatedPendingKeys = pendingRemovalKeys
        updatedPendingKeys.insert(key)
        pendingRemovalKeys = updatedPendingKeys
        if suppressAutoSync {
            var updatedSuppressedKeys = suppressedKeys
            updatedSuppressedKeys.insert(key)
            suppressedKeys = updatedSuppressedKeys
        }
        try await ensureFullAccess(promptIfNeeded: false)
        try client.remove(
            identifier: record.eventIdentifier,
            lastStartDate: record.lastStartDate,
            key: key
        )
        var updated = records
        updated.removeValue(forKey: key)
        records = updated
        updatedPendingKeys.remove(key)
        pendingRemovalKeys = updatedPendingKeys
    }

    func retryPendingRemovals() async throws {
        for key in pendingRemovalKeys {
            try await remove(key: key)
        }
    }

    func removeManagedEvents(category: AppleCalendarSyncCategory) async throws {
        let matchingKeys = records.keys.filter { key in
            switch category {
            case .selection: key.hasPrefix("selection-") && key.hasSuffix("-start")
            case .deadline: key.hasPrefix("selection-") && key.hasSuffix("-deadline")
            case .task: key.hasPrefix("task-")
            }
        }
        var firstError: Error?
        for key in matchingKeys where records[key]?.automatically == true {
            do {
                try await remove(key: key)
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        if let firstError { throw firstError }
    }

    func removeAllManagedEvents(
        matching descriptors: [AppleCalendarEventDescriptor]
    ) async throws {
        let existingRecords = records
        guard existingRecords.isEmpty == false || client.hasFullAccess else {
            return
        }
        try await ensureFullAccess(promptIfNeeded: false)

        struct RemovalTarget {
            let identifier: String?
            let lastStartDate: Date
        }

        var targets = descriptors.reduce(into: [String: RemovalTarget]()) { result, descriptor in
            result[descriptor.key] = RemovalTarget(
                identifier: nil,
                lastStartDate: descriptor.startDate
            )
        }
        for (key, record) in existingRecords {
            targets[key] = RemovalTarget(
                identifier: record.eventIdentifier,
                lastStartDate: record.lastStartDate
            )
        }

        var updatedRecords = existingRecords
        var updatedPendingKeys = pendingRemovalKeys
        var firstError: Error?
        for (key, target) in targets {
            do {
                try client.remove(
                    identifier: target.identifier,
                    lastStartDate: target.lastStartDate,
                    key: key
                )
                updatedRecords.removeValue(forKey: key)
                updatedPendingKeys.remove(key)
            } catch {
                if existingRecords[key] != nil {
                    updatedPendingKeys.insert(key)
                }
                if firstError == nil { firstError = error }
            }
        }
        records = updatedRecords
        pendingRemovalKeys = updatedPendingKeys
        if let firstError { throw firstError }
    }

    func purgePreferences(userID: UUID) {
        let suffix = ".\(userID.uuidString)"
        let keys = [
            "appleCalendarExportRecords.v2\(suffix)",
            "appleCalendarAutoSyncEnabled.v2\(suffix)",
            "appleCalendarAutoSyncSuppressedKeys.v2\(suffix)",
            "appleCalendarPendingRemovalKeys.v2\(suffix)"
        ] + AppleCalendarSyncCategory.allCases.map {
            "appleCalendarAutoSyncCategory.v2.\($0.rawValue)\(suffix)"
        }
        for key in keys {
            defaults.removeObject(forKey: key)
        }
        for key in [
            "appleCalendarExportRecords.v1",
            "appleCalendarAutoSyncEnabled.v1",
            "appleCalendarAutoSyncSuppressedKeys.v1",
            "appleCalendarUserScopeMigration.v2"
        ] {
            defaults.removeObject(forKey: key)
        }
        for category in AppleCalendarSyncCategory.allCases {
            defaults.removeObject(
                forKey: "appleCalendarAutoSyncCategory.v1.\(category.rawValue)"
            )
        }
    }

    func removeSelection(id: UUID) async throws {
        var firstError: Error?
        for kind in [SelectionMilestoneKind.start, .deadline] {
            do {
                try await remove(key: Self.selectionKey(id: id, kind: kind))
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        if let firstError { throw firstError }
    }

    nonisolated static func selectionKey(id: UUID, kind: SelectionMilestoneKind) -> String {
        "selection-\(id.uuidString)-\(kind == .start ? "start" : "deadline")"
    }

    nonisolated static func taskKey(id: UUID) -> String {
        "task-\(id.uuidString)"
    }

    private func ensureFullAccess(promptIfNeeded: Bool) async throws {
        if client.hasFullAccess { return }
        guard promptIfNeeded, try await client.requestFullAccess() else {
            throw AppleCalendarError.accessDenied
        }
    }

    private func upsert(
        _ descriptor: AppleCalendarEventDescriptor,
        automatically: Bool
    ) throws {
        var updatedRecords = records
        let existingRecord = updatedRecords[descriptor.key]
        let saved = try client.save(
            descriptor,
            existingIdentifier: existingRecord?.eventIdentifier,
            lastStartDate: existingRecord?.lastStartDate
        )
        updatedRecords[descriptor.key] = Record(
            eventIdentifier: saved.identifier,
            lastStartDate: saved.startDate,
            automatically: automatically
        )
        records = updatedRecords
    }

    private func categoryKey(_ category: AppleCalendarSyncCategory) -> String {
        scopedKey("appleCalendarAutoSyncCategory.v2.\(category.rawValue)")
    }

    private var recordsKey: String { scopedKey("appleCalendarExportRecords.v2") }
    private var autoSyncKey: String { scopedKey("appleCalendarAutoSyncEnabled.v2") }
    private var suppressedKeysKey: String { scopedKey("appleCalendarAutoSyncSuppressedKeys.v2") }
    private var pendingRemovalKeysKey: String { scopedKey("appleCalendarPendingRemovalKeys.v2") }

    private func scopedKey(_ base: String) -> String {
        "\(base).\(activeUserID?.uuidString ?? "inactive")"
    }

    private func initializeSelectionPreferenceIfNeeded() {
        let selectionKey = categoryKey(.selection)
        guard defaults.object(forKey: selectionKey) == nil else { return }

        let existingKeys = [autoSyncKey, recordsKey, suppressedKeysKey, pendingRemovalKeysKey]
            + AppleCalendarSyncCategory.allCases
                .filter { $0 != .selection }
                .map { categoryKey($0) }
        let hasExistingPreferences = existingKeys.contains { defaults.object(forKey: $0) != nil }
        defaults.set(hasExistingPreferences, forKey: selectionKey)
    }

    private func migrateLegacyPreferencesIfNeeded() {
        let migrationKey = "appleCalendarUserScopeMigration.v2"
        guard defaults.bool(forKey: migrationKey) == false else { return }

        if let data = defaults.data(forKey: "appleCalendarExportRecords.v1"),
           let legacy = try? JSONDecoder().decode([String: LegacyRecord].self, from: data) {
            records = legacy.mapValues {
                Record(
                    eventIdentifier: $0.eventIdentifier,
                    lastStartDate: $0.lastStartDate,
                    automatically: false
                )
            }
        }
        if defaults.object(forKey: "appleCalendarAutoSyncEnabled.v1") != nil {
            defaults.set(defaults.bool(forKey: "appleCalendarAutoSyncEnabled.v1"), forKey: autoSyncKey)
        }
        for category in AppleCalendarSyncCategory.allCases {
            let legacyKey = "appleCalendarAutoSyncCategory.v1.\(category.rawValue)"
            if defaults.object(forKey: legacyKey) != nil {
                defaults.set(defaults.bool(forKey: legacyKey), forKey: categoryKey(category))
            }
        }
        if let suppressed = defaults.stringArray(forKey: "appleCalendarAutoSyncSuppressedKeys.v1") {
            suppressedKeys = Set(suppressed)
        }
        defaults.set(true, forKey: migrationKey)
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


    private var pendingRemovalKeys: Set<String> {
        get {
            Set(defaults.stringArray(forKey: pendingRemovalKeysKey) ?? [])
        }
        set {
            defaults.set(Array(newValue).sorted(), forKey: pendingRemovalKeysKey)
        }
    }
}
