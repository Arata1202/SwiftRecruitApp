import Foundation

enum InputLimits {
    static let companyName = 120
    static let taskTitle = 200
    static let selectionTitle = 120
    static let webURL = 2_048
    static let memo = 10_000
    static let companyInformationTitle = 120
    static let companyInformationBody = 10_000
    static let esTemplateTitle = 120
    static let esTemplateBody = 10_000
    static let selfAnalysisQuestion = 300
    static let selfAnalysisAnswer = 10_000
    static let motivationReason = 1_000

    /// PostgreSQL `char_length` counts Unicode code points rather than Swift
    /// extended grapheme clusters, so use the same unit for client validation.
    static func length(of value: String) -> Int {
        value.unicodeScalars.count
    }
}
