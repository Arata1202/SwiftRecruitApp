import Foundation

// Compare raw text so even whitespace-only edits remain protected until saved.
extension SelfAnalysisAnswerDraft {
    func hasChanges(comparedTo initial: Self) -> Bool {
        category != initial.category || question != initial.question || answer != initial.answer
    }
}

extension CompanyInformationDraft {
    func hasChanges(comparedTo initial: Self) -> Bool {
        category != initial.category
            || title != initial.title
            || body != initial.body
            || hasDate != initial.hasDate
            || (hasDate && LocalDate(date: date) != LocalDate(date: initial.date))
    }
}
