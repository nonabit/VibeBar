import Foundation

public enum ClaudeUsageParserError: LocalizedError, Equatable {
    case missingWindow(String)
    case invalidResetTime(String)

    public var errorDescription: String? {
        switch self {
        case let .missingWindow(name):
            return "Claude 用量响应缺少 \(name)。"
        case let .invalidResetTime(name):
            return "Claude 用量响应中的 \(name) 重置时间无效。"
        }
    }
}

public enum ClaudeUsageParser {
    private struct Response: Decodable {
        let fiveHour: Window?
        let sevenDay: Window?

        enum CodingKeys: String, CodingKey {
            case fiveHour = "five_hour"
            case sevenDay = "seven_day"
        }
    }

    private struct Window: Decodable {
        let utilization: Double
        let resetsAt: String

        enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
        }
    }

    public static func snapshot(from data: Data, updatedAt: Date = Date()) throws -> UsageSnapshot {
        let decoded = try JSONDecoder().decode(Response.self, from: data)

        guard let session = decoded.fiveHour else {
            throw ClaudeUsageParserError.missingWindow("five_hour")
        }
        guard let weekly = decoded.sevenDay else {
            throw ClaudeUsageParserError.missingWindow("seven_day")
        }

        guard let sessionReset = parseResetTime(session.resetsAt) else {
            throw ClaudeUsageParserError.invalidResetTime("five_hour")
        }
        guard let weeklyReset = parseResetTime(weekly.resetsAt) else {
            throw ClaudeUsageParserError.invalidResetTime("seven_day")
        }

        let sessionUsed = normalizedPercent(session.utilization)
        let weeklyUsed = normalizedPercent(weekly.utilization)

        return UsageSnapshot(
            weeklyUsed: sessionUsed,
            weeklyLimit: 100,
            weeklyRemaining: max(0, 100 - sessionUsed),
            weeklyResetAt: sessionReset,
            rateLimitUsed: weeklyUsed,
            rateLimitLimit: 100,
            rateLimitRemaining: max(0, 100 - weeklyUsed),
            rateLimitResetAt: weeklyReset,
            updatedAt: updatedAt)
    }

    private static func normalizedPercent(_ utilization: Double) -> Int {
        let percent = utilization < 1.0 ? utilization * 100.0 : utilization
        return max(0, min(100, Int(percent.rounded())))
    }

    private static func parseResetTime(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }
}
