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

    func testPracticalPublicWebsiteURLs() throws {
        for input in ["realunivlog.com", "https://sub-domain.example.co.jp/jobs?q=a%20b#apply",
                      "http://example.com:8080/", "https://example.com./", "例え.jp/採用",
                      "https://bücher.de/jobs", "https://例え.テスト/", "example.newtld"] {
            let result = try XCTUnwrap(WebURLNormalizer.normalizedString(from: input), input)
            XCTAssertNotNil(URL(string: result)?.host, input)
        }
        XCTAssertEqual(WebURLNormalizer.normalizedString(from: "realunivlog.com"), "https://realunivlog.com")
        XCTAssertEqual(WebURLNormalizer.normalizedString(from: "  https://example.com  "), "https://example.com")
    }

    func testRejectsMalformedOrNonPublicURLs() {
        for input in ["realunivlog", "https://realunivlog", "localhost", "http://127.0.0.1",
                      "https://[::1]", "https://example..com", "https://-example.com",
                      "https://example-.com", "https://exam_ple.com", "https://example.123",
                      "https://user:pass@example.com", "https://user@example.com", "https://@example.com",
                      "ftp://example.com", "javascript:alert(1)", "mailto:hello@example.com",
                      "https:/example.com", "//example.com", "https://example.com:",
                      "https://example.com:0", "https://example.com:65536", "https://example.com:abc",
                      "https://exam ple.com", "https://example.com/a b", "https://example.com/\npath",
                      "https://example.com/\\path", "https://example.com/%", "https://example.com/%GG",
                      "https://%65xample.com", String(repeating: "a", count: 64) + ".com"] {
            XCTAssertNil(WebURLNormalizer.normalizedString(from: input), input)
            XCTAssertFalse(WebURLNormalizer.isValidOrEmpty(input), input)
            XCTAssertThrowsError(try WebURLNormalizer.validatedString(from: input), input)
        }
    }

    func testPersistenceRejectsInvalidInputInsteadOfEncodingNull() throws {
        var draft = CompanyDraft()
        draft.name = "企業"
        draft.url = "realunivlog"
        XCTAssertThrowsError(try CompanyWrite(userID: UUID(), draft: draft))
        XCTAssertThrowsError(try CompanyUpdate(draft: draft))
        draft.url = "realunivlog.com"
        XCTAssertEqual(try CompanyWrite(userID: UUID(), draft: draft).url, "https://realunivlog.com")
        XCTAssertEqual(try CompanyUpdate(draft: draft).url, "https://realunivlog.com")
        draft.url = ""
        let data = try JSONEncoder().encode(CompanyUpdate(draft: draft))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertTrue(json["url"] is NSNull)
        draft.url = "https://example.com/" + String(repeating: "a", count: InputLimits.webURL)
        XCTAssertThrowsError(try CompanyUpdate(draft: draft))
    }

    func testURLInQueryDoesNotBecomeOuterScheme() {
        let path = "example.com/redirect?next=https://example.org"
        XCTAssertEqual(WebURLNormalizer.normalizedString(from: path), "https://" + path)
        XCTAssertEqual(WebURLNormalizer.normalizedString(from: "https://" + path), "https://" + path)
    }

    func testUnchangedLegacyURLIsPreservedButNewInvalidURLIsRejected() throws {
        var draft = CompanyDraft()
        draft.url = "http://localhost"
        XCTAssertEqual(try CompanyUpdate(draft: draft, existingURL: draft.url).url, draft.url)
        XCTAssertThrowsError(try CompanyUpdate(draft: draft, existingURL: "https://example.com"))
        XCTAssertThrowsError(try CompanyWrite(userID: UUID(), draft: draft))
        draft.url = ""
        XCTAssertNil(try CompanyUpdate(draft: draft, existingURL: "http://localhost").url)
    }
}
