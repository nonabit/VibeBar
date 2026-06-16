import Foundation
import Testing
import VibeBarUI

@Test
func parsesClaudeCLIUsageLeftPercentages() throws {
    let output = """
    Current session
    93% left
    Resets Dec 23 at 4:00PM

    Current week (all models)
    79% left
    Resets Dec 29 at 11:00PM
    """

    let snapshot = try ClaudeCLIUsageParser.snapshot(
        from: output,
        updatedAt: Date(timeIntervalSince1970: 0))

    #expect(snapshot.weeklyUsed == 7)
    #expect(snapshot.weeklyLimit == 100)
    #expect(snapshot.weeklyRemaining == 93)
    #expect(snapshot.weeklyResetAt == nil)
    #expect(snapshot.rateLimitUsed == 21)
    #expect(snapshot.rateLimitLimit == 100)
    #expect(snapshot.rateLimitRemaining == 79)
    #expect(snapshot.rateLimitResetAt == nil)
}

@Test
func parsesClaudeCLIUsageUsedPercentages() throws {
    let output = """
    │ Current session          │
    │ 12% used                 │
    │ Resets 11am              │
    │ Current week (all models)│
    │ 40% used                 │
    │ Resets Nov 21            │
    """

    let snapshot = try ClaudeCLIUsageParser.snapshot(
        from: output,
        updatedAt: Date(timeIntervalSince1970: 0))

    #expect(snapshot.weeklyUsed == 12)
    #expect(snapshot.weeklyRemaining == 88)
    #expect(snapshot.rateLimitUsed == 40)
    #expect(snapshot.rateLimitRemaining == 60)
}

@Test
func parsesClaudeCLIUsageWithANSICursorMovements() throws {
    let output = """
    \u{001B}[2CCurre\u{001B}[9Gt\u{001B}[11Gsession
    \u{001B}[53C0%\u{001B}[57Gused
    \u{001B}[3GCurrent\u{001B}[11Gweek\u{001B}[16G(all\u{001B}[21Gmodels)
    \u{001B}[54G61%\u{001B}[58Gleft
    """

    let snapshot = try ClaudeCLIUsageParser.snapshot(
        from: output,
        updatedAt: Date(timeIntervalSince1970: 0))

    #expect(snapshot.weeklyUsed == 0)
    #expect(snapshot.weeklyRemaining == 100)
    #expect(snapshot.rateLimitUsed == 39)
    #expect(snapshot.rateLimitRemaining == 61)
}

@Test
func rejectsClaudeCLIUsageWithoutQuotaWindows() {
    #expect(throws: ClaudeCLIUsageParserError.missingUsageWindow("Current session")) {
        _ = try ClaudeCLIUsageParser.snapshot(from: "You are currently using your subscription.")
    }
}
