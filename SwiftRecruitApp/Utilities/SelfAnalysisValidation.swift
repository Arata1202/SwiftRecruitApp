import Foundation

enum SelfAnalysisValidation {
    static func hasDuplicateMotivationAge(
        _ age: Int,
        excluding pointID: UUID?,
        in points: [MotivationPoint]
    ) -> Bool {
        points.contains { point in
            point.age == age && point.id != pointID
        }
    }
}
