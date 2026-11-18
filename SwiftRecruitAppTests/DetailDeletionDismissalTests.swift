import XCTest
@testable import SwiftRecruitApp

final class DetailDeletionDismissalTests: XCTestCase {
    func testSuccessfulDeletionWaitsForEditorDismissal() {
        var state = DetailDeletionDismissal()
        XCTAssertFalse(state.deletionSucceeded())
        XCTAssertTrue(state.editorDidDismiss())
    }

    func testMissingRecordSessionChangeCancelOrSaveDoesNotCloseDetail() {
        var state = DetailDeletionDismissal()
        XCTAssertFalse(state.editorDidDismiss())
    }

    func testDeletionSuccessAfterSheetDismissalStillClosesDetail() {
        var state = DetailDeletionDismissal()
        XCTAssertFalse(state.editorDidDismiss())
        XCTAssertTrue(state.deletionSucceeded())
    }

    func testReopeningEditorResetsPreviousAcknowledgement() {
        var state = DetailDeletionDismissal()
        XCTAssertFalse(state.deletionSucceeded())
        XCTAssertTrue(state.editorDidDismiss())
        state.editorDidPresent()
        XCTAssertFalse(state.editorDidDismiss())
    }
}
