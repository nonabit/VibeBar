import Foundation
import Testing
import VibeBarUI

@Test
func parsesClaudeOAuthUsageIntoSessionAndWeeklySnapshot() throws {
    let payload = """
    {
      "five_hour": {
        "utilization": 37.4,
        "resets_at": "2026-06-14T10:00:00Z"
      },
      "seven_day": {
        "utilization": 62.6,
        "resets_at": "2026-06-17T10:00:00Z"
      },
      "extra_usage": {
        "is_enabled": true,
        "monthly_limit": 100,
        "used_credits": 12.5,
        "utilization": null,
        "currency": "USD",
        "disabled_reason": null
      }
    }
    """.data(using: .utf8)!

    let snapshot = try ClaudeUsageParser.snapshot(from: payload, updatedAt: Date(timeIntervalSince1970: 0))

    #expect(snapshot.weeklyUsed == 37)
    #expect(snapshot.weeklyLimit == 100)
    #expect(snapshot.weeklyRemaining == 63)
    #expect(snapshot.weeklyResetAt == ISO8601DateFormatter().date(from: "2026-06-14T10:00:00Z"))
    #expect(snapshot.rateLimitUsed == 63)
    #expect(snapshot.rateLimitLimit == 100)
    #expect(snapshot.rateLimitRemaining == 37)
    #expect(snapshot.rateLimitResetAt == ISO8601DateFormatter().date(from: "2026-06-17T10:00:00Z"))
}

@Test
func normalizesFractionalClaudeUtilization() throws {
    let payload = """
    {
      "five_hour": {
        "utilization": 0.251,
        "resets_at": "2026-06-14T10:00:00Z"
      },
      "seven_day": {
        "utilization": 0.8,
        "resets_at": "2026-06-17T10:00:00Z"
      }
    }
    """.data(using: .utf8)!

    let snapshot = try ClaudeUsageParser.snapshot(from: payload, updatedAt: Date(timeIntervalSince1970: 0))

    #expect(snapshot.weeklyUsed == 25)
    #expect(snapshot.weeklyRemaining == 75)
    #expect(snapshot.rateLimitUsed == 80)
    #expect(snapshot.rateLimitRemaining == 20)
}

@Test
func providerTabsIncludeClaude() {
    #expect(ProviderTab.allCases == [.kimi, .codex, .claude, .cursor])
}
