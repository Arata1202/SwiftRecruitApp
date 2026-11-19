import Foundation

struct NotificationTarget: Hashable, Identifiable {
    enum Kind: String, Hashable { case task, selection }
    let kind: Kind
    let itemID: UUID
    let userID: UUID?
    var id: String { "\(kind.rawValue)-\(itemID)" }

    init?(userInfo: [AnyHashable: Any]) {
        guard let kindValue = userInfo["kind"] as? String,
              let kind = Kind(rawValue: kindValue),
              let itemValue = userInfo["item_id"] as? String,
              let itemID = UUID(uuidString: itemValue) else { return nil }
        if let value = userInfo["user_id"],
           (value as? String).flatMap(UUID.init(uuidString:)) == nil { return nil }
        self.kind = kind
        self.itemID = itemID
        userID = (userInfo["user_id"] as? String).flatMap(UUID.init(uuidString:))
    }
}

/// Keeps the latest distinct tap behind existing presentations, never replacing an editor.
struct NotificationRouteState {
    enum Phase: Hashable { case waiting, loading, failed, ready, missing }
    struct Request: Identifiable, Equatable {
        let id = UUID()
        let target: NotificationTarget
        let ownerUserID: UUID
    }
    private(set) var pending: NotificationTarget?
    private(set) var active: Request?
    private(set) var phase: Phase = .waiting
    private var pendingOwnerID: UUID?

    mutating func enqueue(_ target: NotificationTarget, currentUserID: UUID?) {
        guard target != active?.target else { return }
        pending = target
        pendingOwnerID = currentUserID
    }

    mutating func begin(userID: UUID?, blocked: Bool) -> Request? {
        guard active == nil, !blocked, let userID, let target = pending else { return nil }
        pending = nil
        let ownerMatches = pendingOwnerID == nil || pendingOwnerID == userID
        pendingOwnerID = nil
        guard ownerMatches else { return nil }
        let request = Request(target: target, ownerUserID: userID)
        active = request
        phase = target.userID == nil || target.userID == userID ? .loading : .missing
        return request
    }

    mutating func finish(_ request: Request, currentUserID: UUID?, succeeded: Bool, exists: Bool) {
        guard active == request, phase == .loading,
              currentUserID == request.ownerUserID,
              request.target.userID == nil || request.target.userID == currentUserID else { return }
        phase = succeeded ? (exists ? .ready : .missing) : .failed
    }

    mutating func retry() { if phase == .failed { phase = .loading } }
    mutating func dismiss() { active = nil; phase = .waiting }
    mutating func reset() { self = NotificationRouteState() }
}
