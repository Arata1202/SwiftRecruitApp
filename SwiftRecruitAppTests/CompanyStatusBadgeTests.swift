import SwiftUI
import XCTest
@testable import SwiftRecruitApp

final class CompanyStatusBadgeTests: XCTestCase {
    @MainActor
    func testBadgeRetainsItsTitleWhenParentRequestsOnlyIcons() throws {
        for status in CompanyStatus.allCases {
            for size in [DynamicTypeSize.large, .accessibility5] {
                let badge = CompanyStatusBadge(status: status)
                    .fixedSize()
                    .environment(\.dynamicTypeSize, size)
                let reference = try XCTUnwrap(ImageRenderer(content: badge.labelStyle(.titleAndIcon)).uiImage)
                let inIconOnlyParent = try XCTUnwrap(ImageRenderer(content: badge.labelStyle(.iconOnly)).uiImage)
                XCTAssertEqual(inIconOnlyParent.size, reference.size, "\(status.title), \(size)")
            }
        }
    }
}
