import Foundation

public struct UsageSnapshot {
    public let weeklyUsed: Int
    public let weeklyLimit: Int
    public let weeklyRemaining: Int
    public let weeklyResetAt: Date?

    public let rateLimitUsed: Int?
    public let rateLimitLimit: Int?
    public let rateLimitRemaining: Int?
    public let rateLimitResetAt: Date?

    public let updatedAt: Date

    public init(
        weeklyUsed: Int,
        weeklyLimit: Int,
        weeklyRemaining: Int,
        weeklyResetAt: Date?,
        rateLimitUsed: Int?,
        rateLimitLimit: Int?,
        rateLimitRemaining: Int?,
        rateLimitResetAt: Date?,
        updatedAt: Date)
    {
        self.weeklyUsed = weeklyUsed
        self.weeklyLimit = weeklyLimit
        self.weeklyRemaining = weeklyRemaining
        self.weeklyResetAt = weeklyResetAt
        self.rateLimitUsed = rateLimitUsed
        self.rateLimitLimit = rateLimitLimit
        self.rateLimitRemaining = rateLimitRemaining
        self.rateLimitResetAt = rateLimitResetAt
        self.updatedAt = updatedAt
    }

    public var weeklyUsedPercent: Int {
        guard self.weeklyLimit > 0 else { return 0 }
        return Int((Double(self.weeklyUsed) / Double(self.weeklyLimit) * 100.0).rounded())
    }

    public var rateLimitUsedPercent: Int? {
        guard let used = self.rateLimitUsed, let limit = self.rateLimitLimit, limit > 0 else { return nil }
        return Int((Double(used) / Double(limit) * 100.0).rounded())
    }
}
