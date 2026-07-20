import Foundation

struct Company: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let userID: UUID
    var name: String
    /// Retained for API compatibility with older app versions.
    var priority: Int
    var status: CompanyStatus
    var url: String?
    var memo: String?
    let createdAt: Date
    var updatedAt: Date
    var version: Int = 1

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case name
        case priority
        case status
        case url
        case memo
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case version
    }
}

enum CompanyStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case considering
    case active
    case offer
    case rejected
    case withdrawn

    var id: String { rawValue }

    var title: String {
        switch self {
        case .considering: "検討中"
        case .active: "選考中"
        case .offer: "内定"
        case .rejected: "不採用"
        case .withdrawn: "辞退"
        }
    }

    var systemImage: String {
        switch self {
        case .considering: "bookmark"
        case .active: "clock"
        case .offer: "checkmark.seal.fill"
        case .rejected: "xmark.circle"
        case .withdrawn: "arrow.uturn.backward.circle"
        }
    }
}
