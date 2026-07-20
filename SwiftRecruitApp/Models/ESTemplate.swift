import Foundation

struct ESTemplate: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let userID: UUID
    var category: ESTemplateCategory
    var title: String
    var body: String
    let createdAt: Date
    var updatedAt: Date
    var version: Int = 1

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case category, title, body
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case version
    }
}

enum ESTemplateCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case studentExperience = "student_experience"
    case selfPromotion = "self_promotion"
    case motivation
    case strengths
    case weaknesses
    case custom

    var id: Self { self }

    var title: String {
        switch self {
        case .studentExperience: "ガクチカ"
        case .selfPromotion: "自己PR"
        case .motivation: "志望動機"
        case .strengths: "長所"
        case .weaknesses: "短所"
        case .custom: "自由項目"
        }
    }

    var systemImage: String {
        switch self {
        case .studentExperience: "graduationcap"
        case .selfPromotion: "person.text.rectangle"
        case .motivation: "heart"
        case .strengths: "hand.thumbsup"
        case .weaknesses: "arrow.up.right"
        case .custom: "square.and.pencil"
        }
    }

    var sortOrder: Int { Self.allCases.firstIndex(of: self) ?? Self.allCases.count }
}

struct ESTemplateDraft: Sendable {
    var category: ESTemplateCategory = .studentExperience
    var title = ESTemplateCategory.studentExperience.title
    var body = ""

    init() {}

    init(category: ESTemplateCategory) {
        self.category = category
        title = category.title
    }

    init(template: ESTemplate) {
        category = template.category
        title = template.title
        body = template.body
    }
}
