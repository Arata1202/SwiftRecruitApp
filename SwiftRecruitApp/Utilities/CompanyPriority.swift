import Foundation

enum CompanyPriority {
    static func title(for value: Int) -> String {
        switch value {
        case 1: "1（低）"
        case 2: "2"
        case 3: "3（標準）"
        case 4: "4"
        case 5: "5（高）"
        default: String(value)
        }
    }
}
