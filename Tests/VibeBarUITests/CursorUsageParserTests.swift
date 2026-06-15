import Foundation
import Testing
import VibeBarUI

@Test
func parsesCursorCurrentPeriodUsagePercentagesIntoSnapshot() throws {
    let payload = """
    {
      "billingCycleStart": "1781400000000",
      "billingCycleEnd": "1784078400000",
      "planUsage": {
        "totalSpend": 1530,
        "includedSpend": 1200,
        "bonusSpend": 300,
        "limit": 2000,
        "remainingBonus": true,
        "autoPercentUsed": 72.4,
        "apiPercentUsed": 60.0,
        "totalPercentUsed": 76.5
      },
      "spendLimitUsage": {
        "limitType": "user"
      },
      "enabled": true,
      "displayMessage": ""
    }
    """.data(using: .utf8)!

    let snapshot = try CursorUsageParser.snapshot(from: payload, updatedAt: Date(timeIntervalSince1970: 0))

    #expect(snapshot.weeklyUsed == 77)
    #expect(snapshot.weeklyLimit == 100)
    #expect(snapshot.weeklyRemaining == 23)
    #expect(snapshot.weeklyResetAt == Date(timeIntervalSince1970: 1_784_078_400))
    #expect(snapshot.rateLimitUsed == 60)
    #expect(snapshot.rateLimitLimit == 100)
    #expect(snapshot.rateLimitRemaining == 40)
    #expect(snapshot.rateLimitResetAt == Date(timeIntervalSince1970: 1_784_078_400))
    #expect(snapshot.updatedAt == Date(timeIntervalSince1970: 0))
}

@Test
func fallsBackToCursorIncludedSpendWhenPercentagesAreMissing() throws {
    let payload = """
    {
      "billingCycleEnd": "1784078400000",
      "planUsage": {
        "includedSpend": 1200,
        "limit": 2000
      },
      "enabled": true
    }
    """.data(using: .utf8)!

    let snapshot = try CursorUsageParser.snapshot(from: payload, updatedAt: Date(timeIntervalSince1970: 0))

    #expect(snapshot.weeklyUsed == 60)
    #expect(snapshot.weeklyLimit == 100)
    #expect(snapshot.weeklyRemaining == 40)
    #expect(snapshot.rateLimitUsed == nil)
}

@Test
func rejectsCursorUsageWithoutPlanUsage() throws {
    let payload = """
    {
      "billingCycleStart": "1781400000000",
      "billingCycleEnd": "1784078400000",
      "enabled": true
    }
    """.data(using: .utf8)!

    #expect(throws: CursorUsageParserError.missingPlanUsage) {
        _ = try CursorUsageParser.snapshot(from: payload, updatedAt: Date(timeIntervalSince1970: 0))
    }
}

@Test
func parsesCursorPlanName() throws {
    let payload = """
    {
      "planInfo": {
        "planName": "Pro+",
        "includedAmountCents": 7000,
        "price": "$60",
        "billingCycleEnd": "1784078400000"
      },
      "nextUpgrade": {}
    }
    """.data(using: .utf8)!

    #expect(try CursorUsageParser.planName(from: payload) == "Pro+")
}
