import Foundation
import XCTest
@testable import SwiftRecruitApp

final class SelectionStatusUpdateTests: XCTestCase {
    func testStatusPayloadContainsOnlyStatus() throws {
        for status in SelectionStepStatus.allCases {
            let data = try JSONEncoder().encode(SelectionStatusUpdate(status: status))
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
            XCTAssertEqual(object, ["status": status.rawValue])
        }
    }
}
