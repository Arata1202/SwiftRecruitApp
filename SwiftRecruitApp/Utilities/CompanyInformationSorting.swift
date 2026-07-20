import Foundation

enum CompanyInformationSorting {
    static func sorted(_ items: [CompanyInformationItem]) -> [CompanyInformationItem] {
        items.sorted { lhs, rhs in
            if lhs.category.sortOrder != rhs.category.sortOrder {
                return lhs.category.sortOrder < rhs.category.sortOrder
            }
            switch (lhs.occurredOn, rhs.occurredOn) {
            case let (lhsDate?, rhsDate?) where lhsDate != rhsDate:
                return lhsDate > rhsDate
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return lhs.updatedAt > rhs.updatedAt
            }
        }
    }
}
