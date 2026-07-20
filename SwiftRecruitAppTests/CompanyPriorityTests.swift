import XCTest
@testable import SwiftRecruitApp

final class CompanyPriorityTests: XCTestCase {
    func testPriorityLabelsExplainScale() {
        XCTAssertEqual(CompanyPriority.title(for: 1), "1（低）")
        XCTAssertEqual(CompanyPriority.title(for: 3), "3（標準）")
        XCTAssertEqual(CompanyPriority.title(for: 5), "5（高）")
    }
}
