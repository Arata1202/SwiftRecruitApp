import Foundation

struct Company: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let userID: UUID
    var name: String
    var priority: Int
    var status: CompanyStatus
    var url: String?
    var memo: String?
    let createdAt: Date
    var updatedAt: Date

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
    }
}

enum CompanyStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case active
    case offer
    case rejected
    case withdrawn

    var id: String { rawValue }

    var title: String {
        switch self {
        case .active: "選考中"
        case .offer: "内定"
        case .rejected: "不採用"
        case .withdrawn: "辞退"
        }
    }

    var systemImage: String {
        switch self {
        case .active: "figure.run"
        case .offer: "checkmark.seal.fill"
        case .rejected: "xmark.circle"
        case .withdrawn: "arrow.uturn.backward.circle"
        }
    }
}

