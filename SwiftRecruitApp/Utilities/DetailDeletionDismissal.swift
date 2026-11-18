/// Explicit deletion acknowledgement, independent of record/reload availability.
/// Handles either ordering of successful deletion and nested-sheet dismissal.
struct DetailDeletionDismissal {
    private var editorIsPresented = true
    private var didDelete = false

    mutating func editorDidPresent() {
        editorIsPresented = true
        didDelete = false
    }

    mutating func deletionSucceeded() -> Bool {
        didDelete = true
        return !editorIsPresented
    }

    mutating func editorDidDismiss() -> Bool {
        editorIsPresented = false
        return didDelete
    }
}
