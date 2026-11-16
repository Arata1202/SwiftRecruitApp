import Foundation
import XCTest
@testable import SwiftRecruitApp

final class SelectionStatusUpdateTests: XCTestCase {
    func testPayloadContainsOnlyStatusAndNotificationSetting() throws {
        let data = try JSONEncoder().encode(SelectionStatusUpdate(status: .completed, notificationEnabled: false))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), Set(["status", "notification_enabled"]))
        XCTAssertEqual(object["status"] as? String, SelectionStepStatus.completed.rawValue)
        XCTAssertEqual(object["notification_enabled"] as? Bool, false)
    }
}
