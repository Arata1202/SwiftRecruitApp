import Foundation

enum SelfAnalysisSorting {
    static func answers(_ answers: [SelfAnalysisAnswer]) -> [SelfAnalysisAnswer] {
        answers.sorted { lhs, rhs in
            if lhs.category.sortOrder != rhs.category.sortOrder {
                return lhs.category.sortOrder < rhs.category.sortOrder
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    static func motivationPoints(_ points: [MotivationPoint]) -> [MotivationPoint] {
        points.sorted { lhs, rhs in
            if lhs.age != rhs.age { return lhs.age < rhs.age }
            return lhs.updatedAt < rhs.updatedAt
        }
    }
}
