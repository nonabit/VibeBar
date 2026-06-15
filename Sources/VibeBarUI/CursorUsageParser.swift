import Foundation

public enum CursorUsageParserError: LocalizedError, Equatable {
    case missingPlanUsage
    case invalidLimit
    case invalidBillingCycleEnd

    public var errorDescription: String? {
        switch self {
        case .missingPlanUsage:
            return "Cursor 用量响应缺少 planUsage。"
        case .invalidLimit:
            return "Cursor 用量响应中的订阅额度无效。"
        case .invalidBillingCycleEnd:
            return "Cursor 用量响应中的账期结束时间无效。"
        }
    }
}

public enum CursorUsageParser {
    private struct UsageResponse: Decodable {
        let billingCycleEnd: MillisecondsTimestamp
        let planUsage: PlanUsage?
    }

    private struct PlanInfoResponse: Decodable {
        let planInfo: PlanInfo?
    }

    private struct PlanInfo: Decodable {
        let planName: String?
    }

    private struct PlanUsage: Decodable {
        let includedSpend: Int
        let limit: Int
        let apiPercentUsed: Double?
        let totalPercentUsed: Double?

        enum CodingKeys: String, CodingKey {
            case includedSpend
            case limit
            case apiPercentUsed
            case totalPercentUsed
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.includedSpend = try container.decodeIfPresent(Int.self, forKey: .includedSpend) ?? 0
            self.limit = try container.decodeIfPresent(Int.self, forKey: .limit) ?? 0
            self.apiPercentUsed = try container.decodeIfPresent(Double.self, forKey: .apiPercentUsed)
            self.totalPercentUsed = try container.decodeIfPresent(Double.self, forKey: .totalPercentUsed)
        }
    }

    private struct MillisecondsTimestamp: Decodable {
        let value: Int64

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self),
               let value = Int64(string)
            {
                self.value = value
                return
            }
            self.value = try container.decode(Int64.self)
        }
    }

    public static func snapshot(from data: Data, updatedAt: Date = Date()) throws -> UsageSnapshot {
        let decoded = try JSONDecoder().decode(UsageResponse.self, from: data)

        guard let planUsage = decoded.planUsage else {
            throw CursorUsageParserError.missingPlanUsage
        }
        guard planUsage.limit > 0 else {
            throw CursorUsageParserError.invalidLimit
        }
        guard decoded.billingCycleEnd.value > 0 else {
            throw CursorUsageParserError.invalidBillingCycleEnd
        }

        let usedPercent = normalizedPercent(
            planUsage.totalPercentUsed ?? (Double(max(0, planUsage.includedSpend)) / Double(planUsage.limit) * 100.0))
        let apiUsedPercent = planUsage.apiPercentUsed.map(normalizedPercent)
        let resetAt = Date(timeIntervalSince1970: TimeInterval(decoded.billingCycleEnd.value) / 1000.0)

        return UsageSnapshot(
            weeklyUsed: usedPercent,
            weeklyLimit: 100,
            weeklyRemaining: max(0, 100 - usedPercent),
            weeklyResetAt: resetAt,
            rateLimitUsed: apiUsedPercent,
            rateLimitLimit: apiUsedPercent == nil ? nil : 100,
            rateLimitRemaining: apiUsedPercent.map { max(0, 100 - $0) },
            rateLimitResetAt: apiUsedPercent == nil ? nil : resetAt,
            updatedAt: updatedAt)
    }

    public static func planName(from data: Data) throws -> String? {
        let decoded = try JSONDecoder().decode(PlanInfoResponse.self, from: data)
        let trimmed = decoded.planInfo?.planName?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private static func normalizedPercent(_ raw: Double) -> Int {
        max(0, min(100, Int(raw.rounded())))
    }
}
