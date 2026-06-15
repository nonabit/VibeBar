import Foundation
import Testing
import VibeBarUI

@Test
func parsesOpenUsageClaudeProgressLinesIntoSnapshot() throws {
    let payload = """
    {
      "providerId": "claude",
      "displayName": "Claude",
      "plan": "Max 5x",
      "lines": [
        {
          "type": "progress",
          "label": "Session",
          "used": 42.0,
          "limit": 100.0,
          "format": { "kind": "percent" },
          "resetsAt": "2026-03-26T13:00:00.161Z"
        },
        {
          "type": "progress",
          "label": "Weekly",
          "used": 63.0,
          "limit": 100.0,
          "format": { "kind": "percent" },
          "resetsAt": "2026-03-31T13:00:00Z"
        },
        {
          "type": "text",
          "label": "Today",
          "value": "$5.17"
        }
      ],
      "fetchedAt": "2026-03-26T11:16:29Z"
    }
    """.data(using: .utf8)!

    let result = try OpenUsageSnapshotParser.claudeUsage(from: payload)

    #expect(result.planType == "Max 5x")
    #expect(result.snapshot.weeklyUsed == 42)
    #expect(result.snapshot.weeklyLimit == 100)
    #expect(result.snapshot.weeklyRemaining == 58)
    #expect(result.snapshot.weeklyResetAt == parseOpenUsageTestDate("2026-03-26T13:00:00.161Z"))
    #expect(result.snapshot.rateLimitUsed == 63)
    #expect(result.snapshot.rateLimitLimit == 100)
    #expect(result.snapshot.rateLimitRemaining == 37)
    #expect(result.snapshot.rateLimitResetAt == parseOpenUsageTestDate("2026-03-31T13:00:00Z"))
    #expect(result.snapshot.updatedAt == parseOpenUsageTestDate("2026-03-26T11:16:29Z"))
}

@Test
func rejectsOpenUsageSnapshotWithoutSessionProgress() throws {
    let payload = """
    {
      "providerId": "claude",
      "displayName": "Claude",
      "lines": [
        { "type": "text", "label": "Today", "value": "$5.17" }
      ],
      "fetchedAt": "2026-03-26T11:16:29Z"
    }
    """.data(using: .utf8)!

    #expect(throws: OpenUsageSnapshotParserError.missingSessionProgress) {
        _ = try OpenUsageSnapshotParser.claudeUsage(from: payload)
    }
}

private func parseOpenUsageTestDate(_ value: String) -> Date? {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractional.date(from: value) {
        return date
    }

    return ISO8601DateFormatter().date(from: value)
}
