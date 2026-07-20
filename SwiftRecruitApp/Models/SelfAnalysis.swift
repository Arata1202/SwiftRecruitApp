import Foundation

struct SelfAnalysisAnswer: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let userID: UUID
    var category: SelfAnalysisCategory
    var question: String
    var answer: String
    let createdAt: Date
    var updatedAt: Date
    var version: Int = 1

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case category, question, answer
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case version
    }
}

enum SelfAnalysisCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case values
    case strengths
    case interests
    case workStyle = "work_style"
    case future
    case custom

    var id: Self { self }

    var title: String {
        switch self {
        case .values: "価値観"
        case .strengths: "強み・弱み"
        case .interests: "興味・関心"
        case .workStyle: "働き方"
        case .future: "将来像"
        case .custom: "自由質問"
        }
    }

    var defaultQuestion: String {
        switch self {
        case .values: "仕事を通じて大切にしたいことは？"
        case .strengths: "自分の強みと、それが表れた経験は？"
        case .interests: "時間を忘れて取り組めることは？"
        case .workStyle: "どのような環境や働き方なら力を発揮できる？"
        case .future: "5年後、どのような自分になっていたい？"
        case .custom: ""
        }
    }

    var sortOrder: Int { Self.allCases.firstIndex(of: self) ?? Self.allCases.count }
}

struct SelfAnalysisAnswerDraft: Sendable {
    var category: SelfAnalysisCategory = .values
    var question = SelfAnalysisCategory.values.defaultQuestion
    var answer = ""

    init() {}

    init(category: SelfAnalysisCategory) {
        self.category = category
        question = category.defaultQuestion
    }

    init(answer: SelfAnalysisAnswer) {
        category = answer.category
        question = answer.question
        self.answer = answer.answer
    }
}

struct MotivationPoint: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let userID: UUID
    var age: Int
    var happiness: Int
    var reason: String
    let createdAt: Date
    var updatedAt: Date
    var version: Int = 1

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case age, happiness, reason
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case version
    }
}

struct MotivationPointDraft: Sendable {
    var age = 18
    var happiness = 5
    var reason = ""

    init() {}

    init(point: MotivationPoint) {
        age = point.age
        happiness = point.happiness
        reason = point.reason
    }
}
