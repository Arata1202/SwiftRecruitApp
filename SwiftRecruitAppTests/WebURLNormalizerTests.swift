import XCTest
@testable import SwiftRecruitApp

final class WebURLNormalizerTests: XCTestCase {
    func testAddsHTTPSWhenSchemeIsMissing() {
        XCTAssertEqual(
            WebURLNormalizer.normalizedString(from: "example.com/jobs"),
            "https://example.com/jobs"
        )
    }

    func testKeepsHTTPSURL() {
        XCTAssertEqual(
            WebURLNormalizer.normalizedString(from: "https://example.com/jobs"),
            "https://example.com/jobs"
        )
    }

    func testRejectsUnsupportedScheme() {
        XCTAssertNil(WebURLNormalizer.normalizedString(from: "javascript:alert(1)"))
    }

    func testEmptyValueIsValid() {
        XCTAssertTrue(WebURLNormalizer.isValidOrEmpty("  "))
    }
}
