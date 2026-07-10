import Foundation

enum PendingNotificationStore {
    private static let kindKey = "pendingNotification.kind"
    private static let itemIDKey = "pendingNotification.itemID"
    private static let companyIDKey = "pendingNotification.companyID"

    static func save(userInfo: [AnyHashable: Any]) {
        guard let kind = userInfo["kind"] as? String,
              let itemID = userInfo["item_id"] as? String
        else { return }

        let defaults = UserDefaults.standard
        defaults.set(kind, forKey: kindKey)
        defaults.set(itemID, forKey: itemIDKey)
        defaults.set(userInfo["company_id"] as? String, forKey: companyIDKey)
    }

    static func take() -> [AnyHashable: Any]? {
        let defaults = UserDefaults.standard
        guard let kind = defaults.string(forKey: kindKey),
              let itemID = defaults.string(forKey: itemIDKey)
        else { return nil }

        var userInfo: [AnyHashable: Any] = [
            "kind": kind,
            "item_id": itemID,
        ]
        if let companyID = defaults.string(forKey: companyIDKey) {
            userInfo["company_id"] = companyID
        }
        clear()
        return userInfo
    }

    static func clear() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: kindKey)
        defaults.removeObject(forKey: itemIDKey)
        defaults.removeObject(forKey: companyIDKey)
    }
}
