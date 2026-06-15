import Foundation
import Testing
import VibeBarUI

@Test
func parsesRetryAfterDelaySeconds() {
    let now = Date(timeIntervalSince1970: 1_000)

    #expect(UsageRefreshPolicy.retryAfterDate(from: "120", now: now) == Date(timeIntervalSince1970: 1_120))
}

@Test
func parsesRetryAfterHTTPDate() {
    let now = Date(timeIntervalSince1970: 1_445_415_960)

    #expect(
        UsageRefreshPolicy.retryAfterDate(from: "Wed, 21 Oct 2015 07:28:00 GMT", now: now)
            == Date(timeIntervalSince1970: 1_445_412_480))
}

@Test
func skipsRefreshWithinMinimumIntervalOnlyWhenCacheExists() {
    var policy = UsageRefreshPolicy(minimumFetchInterval: 300, defaultRateLimitBackoff: 300)
    let fetchedAt = Date(timeIntervalSince1970: 10)

    policy.recordSuccess(at: fetchedAt)

    #expect(
        policy.skipReason(at: Date(timeIntervalSince1970: 120), hasCachedSnapshot: true)
            == .minimumInterval(until: Date(timeIntervalSince1970: 310)))
    #expect(policy.skipReason(at: Date(timeIntervalSince1970: 120), hasCachedSnapshot: false) == nil)
}

@Test
func rateLimitRetryAfterBlocksSubsequentRefreshes() {
    var policy = UsageRefreshPolicy(minimumFetchInterval: 300, defaultRateLimitBackoff: 300)
    let limitedAt = Date(timeIntervalSince1970: 50)

    let retryAt = policy.recordRateLimit(retryAfterHeader: "90", at: limitedAt)

    #expect(retryAt == Date(timeIntervalSince1970: 140))
    #expect(
        policy.skipReason(at: Date(timeIntervalSince1970: 100), hasCachedSnapshot: true)
            == .rateLimited(until: Date(timeIntervalSince1970: 140)))
}

@Test
func invalidRetryAfterUsesDefaultBackoff() {
    var policy = UsageRefreshPolicy(minimumFetchInterval: 300, defaultRateLimitBackoff: 180)
    let limitedAt = Date(timeIntervalSince1970: 50)

    let retryAt = policy.recordRateLimit(retryAfterHeader: "not-a-date", at: limitedAt)

    #expect(retryAt == Date(timeIntervalSince1970: 230))
}
