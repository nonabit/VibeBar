import Testing
import VibeBarUI

@Test
func fallsBackToClaudeCLIBeforeClaudeWebWhenOAuthIsRateLimited() {
    let nextSources = ClaudeUsageFallbackPolicy.nextSources(
        after: .oauthRateLimited,
        hasClaudeCLI: true,
        hasClaudeWebSession: true,
        hasCachedOAuthSnapshot: true)

    #expect(nextSources == [.claudeCLI, .claudeWebAPI, .cachedOAuthSnapshot])
}

@Test
func fallsBackToClaudeCLIBeforeCacheWhenOAuthIsRateLimitedAndNoWebSessionExists() {
    let nextSources = ClaudeUsageFallbackPolicy.nextSources(
        after: .oauthRateLimited,
        hasClaudeCLI: true,
        hasClaudeWebSession: false,
        hasCachedOAuthSnapshot: true)

    #expect(nextSources == [.claudeCLI, .cachedOAuthSnapshot])
}

@Test
func fallsBackToClaudeWebWhenOAuthIsRateLimitedAndNoClaudeCLIExists() {
    let nextSources = ClaudeUsageFallbackPolicy.nextSources(
        after: .oauthRateLimited,
        hasClaudeCLI: false,
        hasClaudeWebSession: true,
        hasCachedOAuthSnapshot: true)

    #expect(nextSources == [.claudeWebAPI, .cachedOAuthSnapshot])
}

@Test
func fallsBackToClaudeCLIWhenOAuthCredentialsAreUnavailable() {
    let nextSources = ClaudeUsageFallbackPolicy.nextSources(
        after: .oauthUnavailable,
        hasClaudeCLI: true,
        hasClaudeWebSession: true,
        hasCachedOAuthSnapshot: false)

    #expect(nextSources == [.claudeCLI, .claudeWebAPI])
}

@Test
func describesFallbackFailuresWhenOAuthIsRateLimited() {
    let message = ClaudeUsageFallbackPolicy.rateLimitedMessage(
        retryText: nil,
        fallbackFailures: [
            "Claude CLI fallback 失败：/usage 超时。",
            "Claude Web fallback 失败：Claude Web API 被 Cloudflare 拦截（HTTP 403）。",
        ],
        isShowingCachedData: false)

    #expect(message == "Claude 用量接口已限流，Claude CLI fallback 失败：/usage 超时；Claude Web fallback 失败：Claude Web API 被 Cloudflare 拦截（HTTP 403）。")
}

@Test
func includesFallbackFailuresInStaleCacheMessage() {
    let message = ClaudeUsageFallbackPolicy.rateLimitedMessage(
        retryText: "5 分钟",
        fallbackFailures: [
            "Claude CLI fallback 失败：没有解析到 /usage 面板。",
            "Claude Web fallback 失败：Claude Web API 返回 HTTP 500。",
        ],
        isShowingCachedData: true)

    #expect(message == "Claude 用量接口限流，Claude CLI fallback 失败：没有解析到 /usage 面板；Claude Web fallback 失败：Claude Web API 返回 HTTP 500；显示缓存数据；约 5 分钟 后重试。")
}
