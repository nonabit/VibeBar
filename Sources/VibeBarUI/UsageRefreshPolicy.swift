import Foundation

public enum UsageRefreshSkipReason: Equatable {
    case minimumInterval(until: Date)
    case rateLimited(until: Date)
}

public struct UsageRefreshPolicy {
    public let minimumFetchInterval: TimeInterval
    public let defaultRateLimitBackoff: TimeInterval

    public private(set) var lastFetchAt: Date?
    public private(set) var rateLimitedUntil: Date?

    public init(
        minimumFetchInterval: TimeInterval = 5 * 60,
        defaultRateLimitBackoff: TimeInterval = 5 * 60)
    {
        self.minimumFetchInterval = minimumFetchInterval
        self.defaultRateLimitBackoff = defaultRateLimitBackoff
    }

    public func skipReason(at now: Date = Date(), hasCachedSnapshot: Bool) -> UsageRefreshSkipReason? {
        if let rateLimitedUntil, now < rateLimitedUntil {
            return .rateLimited(until: rateLimitedUntil)
        }

        guard hasCachedSnapshot, let lastFetchAt else {
            return nil
        }

        let nextAllowedFetchAt = lastFetchAt.addingTimeInterval(self.minimumFetchInterval)
        if now < nextAllowedFetchAt {
            return .minimumInterval(until: nextAllowedFetchAt)
        }
        return nil
    }

    public mutating func recordSuccess(at now: Date = Date()) {
        self.lastFetchAt = now
        self.rateLimitedUntil = nil
    }

    @discardableResult
    public mutating func recordRateLimit(retryAfterHeader: String?, at now: Date = Date()) -> Date {
        let retryAt = Self.retryAfterDate(from: retryAfterHeader, now: now)
            ?? now.addingTimeInterval(self.defaultRateLimitBackoff)
        self.rateLimitedUntil = retryAt
        return retryAt
    }

    public static func retryAfterDate(from header: String?, now: Date = Date()) -> Date? {
        guard let value = header?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        if let seconds = Double(value), seconds >= 0 {
            return now.addingTimeInterval(seconds)
        }

        return Self.httpDateFormatter.date(from: value)
    }

    private static var httpDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }
}
