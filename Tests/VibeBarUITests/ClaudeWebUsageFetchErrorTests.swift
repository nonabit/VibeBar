import Testing
import VibeBarUI

@Test
func describesCloudflareChallengeAsClaudeWebBlocker() {
    let error = ClaudeWebUsageFetchError.badStatus(403, isCloudflareChallenge: true)

    #expect(error.errorDescription == "Claude Web API 被 Cloudflare 拦截（HTTP 403）。")
}

@Test
func describesPlainClaudeWebHTTPFailure() {
    let error = ClaudeWebUsageFetchError.badStatus(500, isCloudflareChallenge: false)

    #expect(error.errorDescription == "Claude Web API 返回 HTTP 500。")
}
