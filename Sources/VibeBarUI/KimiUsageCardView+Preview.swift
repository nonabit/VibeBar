import SwiftUI

#if DEBUG
#Preview("有数据") {
    KimiUsageCardView(
        selectedProvider: .kimi,
        onSelectProvider: nil,
        providerTitle: "Kimi",
        planText: "Pro",
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
        tokenSourceText: "浏览器(Default)",
        updatedText: "2026-02-09 18:30:00",
        weeklyResetText: "20小时后",
        rateResetText: "2小时后",
        lastError: nil)
    .frame(width: 320)
    .padding()
}

#Preview("错误态") {
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
        weeklyResetText: "重置未知",
        rateResetText: "重置未知",
        lastError: "未找到 kimi-auth token")
    .frame(width: 320)
    .padding()
}
#endif
