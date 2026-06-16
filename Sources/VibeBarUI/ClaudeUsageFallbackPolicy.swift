public enum ClaudeUsageFallbackTrigger: Equatable {
    case oauthRateLimited
    case oauthUnavailable
}

public enum ClaudeUsageFallbackSource: Equatable {
    case claudeCLI
    case claudeWebAPI
    case cachedOAuthSnapshot
}

public enum ClaudeUsageFallbackPolicy {
    public static func nextSources(
        after trigger: ClaudeUsageFallbackTrigger,
        hasClaudeCLI: Bool,
        hasClaudeWebSession: Bool,
        hasCachedOAuthSnapshot: Bool)
        -> [ClaudeUsageFallbackSource]
    {
        switch trigger {
        case .oauthRateLimited, .oauthUnavailable:
            var sources: [ClaudeUsageFallbackSource] = []
            if hasClaudeCLI {
                sources.append(.claudeCLI)
            }
            if hasClaudeWebSession {
                sources.append(.claudeWebAPI)
            }
            if hasCachedOAuthSnapshot {
                sources.append(.cachedOAuthSnapshot)
            }
            return sources
        }
    }

    public static func nextSources(
        after trigger: ClaudeUsageFallbackTrigger,
        hasClaudeWebSession: Bool,
        hasCachedOAuthSnapshot: Bool)
        -> [ClaudeUsageFallbackSource]
    {
        nextSources(
            after: trigger,
            hasClaudeCLI: false,
            hasClaudeWebSession: hasClaudeWebSession,
            hasCachedOAuthSnapshot: hasCachedOAuthSnapshot)
    }

    public static func rateLimitedMessage(
        retryText: String?,
        fallbackFailures: [String],
        isShowingCachedData: Bool)
        -> String
    {
        let normalizedFailures = fallbackFailures
            .map(stripTrailingSentencePunctuation)
            .filter { !$0.isEmpty }
        var message = isShowingCachedData ? "Claude 用量接口限流" : "Claude 用量接口已限流"

        if !normalizedFailures.isEmpty {
            message += "，\(normalizedFailures.joined(separator: "；"))"
        }

        if isShowingCachedData {
            message += "；显示缓存数据"
        }

        if let retryText, !retryText.isEmpty {
            message += "；约 \(retryText) 后重试"
        }

        return message + "。"
    }

    public static func rateLimitedMessage(
        retryText: String?,
        webFallbackFailure: String?,
        isShowingCachedData: Bool)
        -> String
    {
        let fallbackFailures = webFallbackFailure.map { ["Claude Web fallback 失败：\($0)"] } ?? []
        return rateLimitedMessage(
            retryText: retryText,
            fallbackFailures: fallbackFailures,
            isShowingCachedData: isShowingCachedData)
    }

    private static func stripTrailingSentencePunctuation(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while result.last == "。" || result.last == "." {
            result.removeLast()
        }
        return result
    }
}
