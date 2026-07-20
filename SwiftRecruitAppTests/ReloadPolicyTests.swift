import Foundation
import XCTest
@testable import SwiftRecruitApp

final class ReloadPolicyTests: XCTestCase {
    func testReloadsWhenNeverLoadedOrIntervalElapsed() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)

        XCTAssertTrue(ReloadPolicy.shouldReload(lastSuccessfulReloadAt: nil, now: now))
        XCTAssertTrue(ReloadPolicy.shouldReload(
            lastSuccessfulReloadAt: now.addingTimeInterval(-300), now: now
        ))
    }

    func testDoesNotReloadFreshData() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)

        XCTAssertFalse(ReloadPolicy.shouldReload(
            lastSuccessfulReloadAt: now.addingTimeInterval(-299), now: now
        ))
    }
}
