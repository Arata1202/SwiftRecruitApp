import Foundation

struct CompanyInformationItem: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let userID: UUID
    let companyID: UUID
    var category: CompanyInformationCategory
    var title: String
    var body: String
    var occurredOn: LocalDate?
    let createdAt: Date
    var updatedAt: Date
    var version: Int = 1

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case companyID = "company_id"
        case category, title, body
        case occurredOn = "occurred_on"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case version
    }
}

enum CompanyInformationCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case research
    case motivation
    case interview
    case questions
    case custom

    var id: Self { self }

    var title: String {
        switch self {
        case .research: "企業研究"
        case .motivation: "志望理由"
        case .interview: "面接記録"
        case .questions: "逆質問"
        case .custom: "自由項目"
        }
    }

    var systemImage: String {
        switch self {
        case .research: "building.2"
        case .motivation: "heart"
        case .interview: "person.2"
        case .questions: "questionmark.bubble"
        case .custom: "square.and.pencil"
        }
    }

    var titlePlaceholder: String {
        switch self {
        case .research: "例：競合との違い"
        case .motivation: "例：この企業を志望する理由"
        case .interview: "例：一次面接"
        case .questions: "例：現場社員への質問"
        case .custom: "例：福利厚生について"
        }
    }

    var sortOrder: Int {
        Self.allCases.firstIndex(of: self) ?? Self.allCases.count
    }
}

struct CompanyInformationDraft: Sendable {
    var category: CompanyInformationCategory = .research
    var title = ""
    var body = ""
    var hasDate = false
    var date = Date()

    init() {}

    init(category: CompanyInformationCategory) {
        self.category = category
        hasDate = category == .interview
    }

    init(item: CompanyInformationItem) {
        category = item.category
        title = item.title
        body = item.body
        hasDate = item.occurredOn != nil
        date = item.occurredOn?.date() ?? Date()
    }
}
