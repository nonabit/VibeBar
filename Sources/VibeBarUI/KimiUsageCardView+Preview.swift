import SwiftUI

#if DEBUG
#Preview("With Data") {
    KimiUsageCardView(
        selectedProvider: .kimi,
        onSelectProvider: nil,
        providerTitle: "Kimi",
        planText: "Allegretto",
        primaryTitle: "Session",
        secondaryTitle: "Weekly",
        snapshot: KimiUsageSnapshot(
            weeklyUsed: 320,
            weeklyLimit: 1024,
            weeklyRemaining: 704,
            weeklyResetAt: Date().addingTimeInterval(20 * 3600),
            rateLimitUsed: 120,
            rateLimitLimit: 200,
            rateLimitRemaining: 80,
            rateLimitResetAt: Date().addingTimeInterval(2 * 3600),
            updatedAt: Date()),
        tokenSourceText: "Browser (Default)",
        updatedText: "2026-02-09 18:30:00",
        weeklyResetText: "Resets in 20h",
        rateResetText: "Resets in 2h",
        lastError: nil)
    .frame(width: 320)
    .padding()
}

#Preview("Error State") {
    KimiUsageCardView(
        selectedProvider: .codex,
        onSelectProvider: nil,
        providerTitle: "Codex",
        planText: "Plus",
        primaryTitle: "Session",
        secondaryTitle: "Weekly",
        snapshot: nil,
        tokenSourceText: "-",
        updatedText: "-",
        weeklyResetText: "Reset time unavailable",
        rateResetText: "Reset time unavailable",
        lastError: "kimi-auth token not found")
    .frame(width: 320)
    .padding()
}
#endif
