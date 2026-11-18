import Foundation

enum ESTemplateSorting {
    static func sorted(_ templates: [ESTemplate]) -> [ESTemplate] {
        templates.sorted { lhs, rhs in
            if lhs.category.sortOrder != rhs.category.sortOrder {
                return lhs.category.sortOrder < rhs.category.sortOrder
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }
}
