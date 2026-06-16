import Foundation

public enum ClaudeCLIUsageParserError: LocalizedError, Equatable {
    case missingUsageWindow(String)
    case invalidPercentage(String)

    public var errorDescription: String? {
        switch self {
        case let .missingUsageWindow(name):
            return "Claude CLI /usage 输出缺少 \(name)。"
        case let .invalidPercentage(line):
            return "Claude CLI /usage 输出中的百分比无效：\(line)。"
        }
    }
}

public enum ClaudeCLIUsageParser {
    private struct WindowUsage {
        let used: Int
        let remaining: Int
    }

    public static func snapshot(from output: String, updatedAt: Date = Date()) throws -> UsageSnapshot {
        let lines = normalizedLines(from: output)
        let session = try usageWindow(named: "Current session", in: lines)
        let weekly = try usageWindow(named: "Current week", in: lines)

        return UsageSnapshot(
            weeklyUsed: session.used,
            weeklyLimit: 100,
            weeklyRemaining: session.remaining,
            weeklyResetAt: nil,
            rateLimitUsed: weekly.used,
            rateLimitLimit: 100,
            rateLimitRemaining: weekly.remaining,
            rateLimitResetAt: nil,
            updatedAt: updatedAt)
    }

    private static func usageWindow(named label: String, in lines: [String]) throws -> WindowUsage {
        guard let labelIndex = lines.firstIndex(where: { matchesUsageLabel($0, label: label) }) else {
            throw ClaudeCLIUsageParserError.missingUsageWindow(label)
        }

        let searchEnd = min(lines.count, labelIndex + 8)
        guard labelIndex + 1 < searchEnd else {
            throw ClaudeCLIUsageParserError.missingUsageWindow(label)
        }

        for line in lines[(labelIndex + 1)..<searchEnd] {
            if isUsageLabel(line),
               !matchesUsageLabel(line, label: label)
            {
                break
            }

            if let usage = try percentageUsage(from: line) {
                return usage
            }
        }

        throw ClaudeCLIUsageParserError.missingUsageWindow(label)
    }

    private static func isUsageLabel(_ line: String) -> Bool {
        matchesUsageLabel(line, label: "Current session")
            || matchesUsageLabel(line, label: "Current week")
    }

    private static func matchesUsageLabel(_ line: String, label: String) -> Bool {
        let compactLine = compactForMatching(line)
        let compactLabel = compactForMatching(label)
        if compactLine.contains(compactLabel) {
            return true
        }

        if label == "Current session" {
            return compactLine.contains("session")
                && (compactLine.contains("current") || compactLine.contains("curre"))
        }
        if label == "Current week" {
            return compactLine.contains("week")
                && (compactLine.contains("current")
                    || compactLine.contains("curre")
                    || compactLine.contains("models"))
        }
        return false
    }

    private static func compactForMatching(_ value: String) -> String {
        value
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func percentageUsage(from line: String) throws -> WindowUsage? {
        let pattern = #"(\d{1,3})\s*%\s*(left|remaining|used)?"#
        let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        let range = NSRange(location: 0, length: (line as NSString).length)
        guard let match = regex.firstMatch(in: line, range: range) else {
            return nil
        }

        let valueRange = match.range(at: 1)
        guard let swiftRange = Range(valueRange, in: line),
              let rawPercent = Int(line[swiftRange])
        else {
            throw ClaudeCLIUsageParserError.invalidPercentage(line)
        }

        let percent = max(0, min(100, rawPercent))
        let qualifier: String
        if match.numberOfRanges > 2,
           let qualifierRange = Range(match.range(at: 2), in: line)
        {
            qualifier = String(line[qualifierRange]).lowercased()
        } else {
            qualifier = ""
        }

        if qualifier == "used" || line.localizedCaseInsensitiveContains("% used") {
            return WindowUsage(used: percent, remaining: 100 - percent)
        }
        return WindowUsage(used: 100 - percent, remaining: percent)
    }

    private static func normalizedLines(from output: String) -> [String] {
        let withoutANSI = removingANSIEscapes(from: output)
        return withoutANSI
            .split(whereSeparator: \.isNewline)
            .map(cleanTerminalLine)
            .filter { !$0.isEmpty }
    }

    private static func cleanTerminalLine(_ line: Substring) -> String {
        let removableCharacters = CharacterSet(charactersIn: "│┃║╎┆┊╏┇┋╽╿╵╷╹╻")
        return String(line)
            .components(separatedBy: removableCharacters)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func removingANSIEscapes(from output: String) -> String {
        let pattern = "\u{001B}\\[[0-?]*[ -/]*[@-~]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return output
        }
        let range = NSRange(location: 0, length: (output as NSString).length)
        return regex.stringByReplacingMatches(in: output, range: range, withTemplate: "")
    }
}
