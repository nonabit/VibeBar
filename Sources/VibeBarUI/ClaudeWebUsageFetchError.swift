import Foundation

public enum ClaudeWebUsageFetchError: LocalizedError, Equatable {
    case network(String)
    case badStatus(Int, isCloudflareChallenge: Bool)
    case parse(String)

    public var errorDescription: String? {
        switch self {
        case let .network(message):
            return "Claude Web API 网络请求失败：\(message)"
        case let .badStatus(statusCode, true):
            return "Claude Web API 被 Cloudflare 拦截（HTTP \(statusCode)）。"
        case let .badStatus(statusCode, false):
            return "Claude Web API 返回 HTTP \(statusCode)。"
        case let .parse(message):
            return "Claude Web API 解析失败：\(message)"
        }
    }
}
