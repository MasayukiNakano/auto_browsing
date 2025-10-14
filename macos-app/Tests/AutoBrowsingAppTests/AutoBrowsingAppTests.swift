import XCTest
@testable import AutoBrowsingApp

final class AutoBrowsingAppTests: XCTestCase {
    func testSampleConfigurationLoads() throws {
        let profiles = try SiteProfileLoader().loadProfiles()
        XCTAssertFalse(profiles.isEmpty)
    }
}
