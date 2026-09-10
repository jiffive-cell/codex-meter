#if canImport(XCTest)
import XCTest
@testable import CodexMeter

final class CodexMeterTests: XCTestCase {
    func testRateLimitResponseDecodesResetCreditsAndPlan() throws {
        let data = Data(#"{"accountId":"a","rateLimits":{"limitId":"codex","limitName":null,"primary":{"usedPercent":57,"windowDurationMins":300,"resetsAt":1788966999},"secondary":{"usedPercent":51,"windowDurationMins":10080,"resetsAt":1789445362},"credits":{"hasCredits":false,"unlimited":false,"balance":"0"},"individualLimit":null,"spendControlReached":false,"planType":"plus","rateLimitReachedType":null},"rateLimitsByLimitId":null,"rateLimitResetCredits":{"availableCount":3,"credits":[{"id":"r1","resetType":"codexRateLimits","status":"available","grantedAt":1,"expiresAt":2,"title":"Full reset","description":null}]}}"#.utf8)
        let response = try JSONDecoder().decode(RateLimitsResponse.self, from: data)
        XCTAssertEqual(response.rateLimits.planType, "plus")
        XCTAssertEqual(response.rateLimits.primary?.windowDurationMins, 300)
        XCTAssertEqual(response.rateLimitResetCredits?.availableCount, 3)
        XCTAssertEqual(response.rateLimitResetCredits?.credits?.first?.title, "Full reset")
    }
}
#endif
