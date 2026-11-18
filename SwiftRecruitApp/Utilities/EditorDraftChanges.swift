import Foundation

// Compare raw text so even whitespace-only edits remain protected until saved.
extension CompanyInformationDraft {
    func hasChanges(comparedTo initial: Self) -> Bool {
        category != initial.category
            || title != initial.title
            || body != initial.body
            || hasDate != initial.hasDate
            || (hasDate && LocalDate(date: date) != LocalDate(date: initial.date))
    }
}
