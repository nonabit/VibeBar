import Foundation

public enum OpenUsageSnapshotParserError: LocalizedError, Equatable {
    case missingSessionProgress
    case invalidFetchedAt
    case invalidProgress(String)

    public var errorDescription: String? {
        switch self {
        case .missingSessionProgress:
            return "OpenUsage Claude 响应缺少 Session 进度。"
        case .invalidFetchedAt:
            return "OpenUsage Claude 响应中的 fetchedAt 无效。"
        case let .invalidProgress(label):
            return "OpenUsage Claude 响应中的 \(label) 进度无效。"
        }
    }
}

public struct OpenUsageProviderUsage {
    public let snapshot: UsageSnapshot
    public let planType: String?
}

public enum OpenUsageSnapshotParser {
    private struct Response: Decodable {
        let plan: String?
        let lines: [Line]
        let fetchedAt: String
    }

    private struct Line: Decodable {
        let type: String
        let label: String
        let used: Double?
        let limit: Double?
        let resetsAt: String?
    }

    private struct Progress {
        let used: Int
        let limit: Int
        let remaining: Int
        let resetsAt: Date?
    }

    public static func claudeUsage(from data: Data) throws -> OpenUsageProviderUsage {
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let fetchedAt = parseDate(decoded.fetchedAt) else {
            throw OpenUsageSnapshotParserError.invalidFetchedAt
        }

        let progressLines = decoded.lines.filter { $0.type == "progress" }
        guard !progressLines.isEmpty else {
            throw OpenUsageSnapshotParserError.missingSessionProgress
        }

        let sessionIndex = progressLines.firstIndex { isSessionLabel($0.label) } ?? progressLines.startIndex
        let sessionLine = progressLines[sessionIndex]
        let weeklyLine = progressLines.enumerated().first { index, line in
            index != sessionIndex && isWeeklyLabel(line.label)
        }?.element

        let session = try progress(from: sessionLine)
        let weekly = try weeklyLine.map(progress)

        return OpenUsageProviderUsage(
            snapshot: UsageSnapshot(
                weeklyUsed: session.used,
                weeklyLimit: session.limit,
                weeklyRemaining: session.remaining,
                weeklyResetAt: session.resetsAt,
                rateLimitUsed: weekly?.used,
                rateLimitLimit: weekly?.limit,
                rateLimitRemaining: weekly?.remaining,
                rateLimitResetAt: weekly?.resetsAt,
                updatedAt: fetchedAt),
            planType: decoded.plan)
    }

    private static func progress(from line: Line) throws -> Progress {
        guard let rawUsed = line.used,
              let rawLimit = line.limit,
              rawLimit > 0
        else {
            throw OpenUsageSnapshotParserError.invalidProgress(line.label)
        }

        let normalizedLimit = rawLimit <= 1 ? rawLimit * 100 : rawLimit
        let normalizedUsed = rawLimit <= 1 && rawUsed <= 1 ? rawUsed * 100 : rawUsed
        let limit = max(1, Int(normalizedLimit.rounded()))
        let used = max(0, min(limit, Int(normalizedUsed.rounded())))

        return Progress(
            used: used,
            limit: limit,
            remaining: max(0, limit - used),
            resetsAt: line.resetsAt.flatMap(parseDate))
    }

    private static func isSessionLabel(_ label: String) -> Bool {
        label.localizedCaseInsensitiveContains("session")
    }

    private static func isWeeklyLabel(_ label: String) -> Bool {
        label.localizedCaseInsensitiveContains("week")
    }

    private static func parseDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }

        return ISO8601DateFormatter().date(from: value)
    }
}
