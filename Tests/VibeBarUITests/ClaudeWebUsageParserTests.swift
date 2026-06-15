import Foundation
import Testing
import VibeBarUI

@Test
func picksClaudeWebOrganizationWithChatCapability() throws {
    let payload = """
    [
      {
        "uuid": "api-only-org",
        "name": "API Only",
        "capabilities": ["api"]
      },
      {
        "uuid": "chat-org",
        "name": "Claude Team",
        "capabilities": ["chat", "api"]
      }
    ]
    """.data(using: .utf8)!

    let organization = try ClaudeWebUsageParser.organization(from: payload)

    #expect(organization.id == "chat-org")
    #expect(organization.name == "Claude Team")
}

@Test
func parsesClaudeWebUsageIntoSnapshot() throws {
    let payload = """
    {
      "five_hour": {
        "utilization": 41,
        "resets_at": "2026-06-15T12:00:00Z"
      },
      "seven_day": {
        "utilization": 68,
        "resets_at": "2026-06-20T12:00:00Z"
      }
    }
    """.data(using: .utf8)!

    let snapshot = try ClaudeWebUsageParser.snapshot(from: payload, updatedAt: Date(timeIntervalSince1970: 0))

    #expect(snapshot.weeklyUsed == 41)
    #expect(snapshot.weeklyRemaining == 59)
    #expect(snapshot.weeklyResetAt == ISO8601DateFormatter().date(from: "2026-06-15T12:00:00Z"))
    #expect(snapshot.rateLimitUsed == 68)
    #expect(snapshot.rateLimitRemaining == 32)
    #expect(snapshot.rateLimitResetAt == ISO8601DateFormatter().date(from: "2026-06-20T12:00:00Z"))
}
