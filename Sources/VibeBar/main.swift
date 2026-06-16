import AppKit
import Foundation
import LocalAuthentication
import Security
import SweetCookieKit
import SwiftUI
import VibeBarUI

private let kimiUsageURL = URL(string: "https://www.kimi.com/apiv2/kimi.gateway.billing.v1.BillingService/GetUsages")!
private let kimiSubscriptionURL = URL(string: "https://www.kimi.com/apiv2/kimi.gateway.order.v1.SubscriptionService/GetSubscription")!
private let kimiConsoleURL = URL(string: "https://www.kimi.com/code/console")!
private let codexUsageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
private let codexUsagePageURL = URL(string: "https://chatgpt.com/codex/settings/usage")!
private let claudeUsageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
private let claudeUsagePageURL = URL(string: "https://claude.ai/settings/usage")!
private let claudeWebOrganizationsURL = URL(string: "https://claude.ai/api/organizations")!
private let claudeWebAPIBaseURL = URL(string: "https://claude.ai/api")!
private let cursorUsageURL = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage")!
private let cursorPlanInfoURL = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetPlanInfo")!
private let cursorUsagePageURL = URL(string: "https://cursor.com/dashboard/usage")!

enum RefreshInterval: TimeInterval, CaseIterable {
    case oneMinute = 60
    case fiveMinutes = 300
    case fifteenMinutes = 900

    var title: String {
        switch self {
        case .oneMinute:
            "每 1 分钟"
        case .fiveMinutes:
            "每 5 分钟"
        case .fifteenMinutes:
            "每 15 分钟"
        }
    }
}

enum TokenSource: CustomStringConvertible {
    case environment
    case browser(String)
    case keychain

    var description: String {
        switch self {
        case .environment:
            return "环境变量"
        case let .browser(label):
            return "浏览器(\(label))"
        case .keychain:
            return "钥匙串"
        }
    }
}

struct TokenResolution {
    let token: String
    let source: TokenSource
}

enum KimiAPIError: LocalizedError {
    case missingToken
    case invalidToken
    case network(String)
    case badStatus(Int, String)
    case parse(String)

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "未找到 kimi-auth token。请先在浏览器登录 Kimi。"
        case .invalidToken:
            return "token 已失效，请重新登录 Kimi。"
        case let .network(message):
            return "网络请求失败: \(message)"
        case let .badStatus(code, body):
            return "接口返回 HTTP \(code): \(body)"
        case let .parse(message):
            return "解析失败: \(message)"
        }
    }
}

final class KeychainStore {
    private let service = "com.vibebar.kimi"
    private let account = "auth-token"

    func readToken() -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecAttrSynchronizable: kCFBooleanFalse as Any,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty
        else {
            return nil
        }
        return token
    }

    func writeToken(_ token: String) {
        let data = Data(token.utf8)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrSynchronizable: kCFBooleanFalse as Any,
        ]

        let attrs: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrSynchronizable: kCFBooleanFalse as Any,
        ]

        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecSuccess {
            return
        }

        var add = query
        add[kSecValueData] = data
        add[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        _ = SecItemAdd(add as CFDictionary, nil)
    }
}

final class KimiTokenProvider {
    private let keychain = KeychainStore()
    private let cookieClient = BrowserCookieClient()

    func resolveToken() throws -> TokenResolution {
        if let envToken = ProcessInfo.processInfo.environment["KIMI_AUTH_TOKEN"],
           !envToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return TokenResolution(token: envToken, source: .environment)
        }

        if let browserToken = fetchFromBrowser() {
            keychain.writeToken(browserToken.token)
            return browserToken
        }

        if let keychainToken = keychain.readToken() {
            return TokenResolution(token: keychainToken, source: .keychain)
        }

        throw KimiAPIError.missingToken
    }

    func refreshFromBrowser() -> TokenResolution? {
        guard let browserToken = fetchFromBrowser() else { return nil }
        keychain.writeToken(browserToken.token)
        return browserToken
    }

    private func fetchFromBrowser() -> TokenResolution? {
        let query = BrowserCookieQuery(
            domains: ["www.kimi.com", "kimi.com"],
            domainMatch: .suffix,
            includeExpired: false)

        for browser in Browser.defaultImportOrder {
            do {
                let stores = try cookieClient.records(matching: query, in: browser)
                for store in stores {
                    let cookies = store.cookies(origin: query.origin)
                    if let auth = cookies.first(where: { $0.name == "kimi-auth" }), !auth.value.isEmpty {
                        return TokenResolution(token: auth.value, source: .browser(store.label))
                    }
                }
            } catch {
                continue
            }
        }
        return nil
    }
}

struct KimiUsageResponse: Decodable {
    struct Usage: Decodable {
        struct Detail: Decodable {
            let limit: String
            let used: String?
            let remaining: String?
            let resetTime: String
        }

        struct RateLimit: Decodable {
            struct Window: Decodable {
                let duration: Int
                let timeUnit: String
            }

            let window: Window
            let detail: Detail
        }

        let scope: String
        let detail: Detail
        let limits: [RateLimit]?
    }

    let usages: [Usage]
}

struct KimiSubscriptionResponse: Decodable {
    struct Membership: Decodable {
        let feature: String?
        let level: String?
    }

    struct Subscription: Decodable {
        struct Goods: Decodable {
            let title: String?
            let membershipLevel: String?

            enum CodingKeys: String, CodingKey {
                case title
                case membershipLevel = "membershipLevel"
            }
        }

        let goods: Goods?
    }

    let subscription: Subscription?
    let purchaseSubscription: Subscription?
    let memberships: [Membership]?

    enum CodingKeys: String, CodingKey {
        case subscription
        case purchaseSubscription = "purchaseSubscription"
        case memberships
    }
}

struct KimiUsageResult {
    let snapshot: UsageSnapshot
    let planName: String?
}

struct CodexAuthResolution {
    let accessToken: String
    let accountId: String?
    let sourceText: String
    let fallbackPlanType: String?
}

enum CodexAPIError: LocalizedError {
    case missingCredentials
    case invalidToken
    case network(String)
    case badStatus(Int, String)
    case parse(String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "未找到 Codex 凭据。请先运行 codex 登录。"
        case .invalidToken:
            return "Codex token 已失效，请重新登录 codex。"
        case let .network(message):
            return "Codex 网络请求失败: \(message)"
        case let .badStatus(code, body):
            return "Codex 接口返回 HTTP \(code): \(body)"
        case let .parse(message):
            return "Codex 解析失败: \(message)"
        }
    }
}

final class CodexCredentialsProvider {
    func resolveCredentials() throws -> CodexAuthResolution {
        if let envToken = ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
           !envToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return CodexAuthResolution(
                accessToken: envToken,
                accountId: nil,
                sourceText: "环境变量(OPENAI_API_KEY)",
                fallbackPlanType: nil)
        }

        let authURL = self.authFileURL()
        guard let data = try? Data(contentsOf: authURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw CodexAPIError.missingCredentials
        }

        if let apiKey = json["OPENAI_API_KEY"] as? String,
           !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return CodexAuthResolution(
                accessToken: apiKey,
                accountId: nil,
                sourceText: "auth.json(OPENAI_API_KEY)",
                fallbackPlanType: nil)
        }

        guard let tokens = json["tokens"] as? [String: Any],
              let accessToken = tokens["access_token"] as? String,
              !accessToken.isEmpty
        else {
            throw CodexAPIError.missingCredentials
        }

        let accountId = tokens["account_id"] as? String
        let fallbackPlanType = Self.extractPlanType(fromIDToken: tokens["id_token"] as? String)
        return CodexAuthResolution(
            accessToken: accessToken,
            accountId: accountId,
            sourceText: "auth.json",
            fallbackPlanType: fallbackPlanType)
    }

    private func authFileURL() -> URL {
        let env = ProcessInfo.processInfo.environment
        if let codexHome = env["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !codexHome.isEmpty
        {
            return URL(fileURLWithPath: codexHome).appendingPathComponent("auth.json")
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex")
            .appendingPathComponent("auth.json")
    }

    private static func extractPlanType(fromIDToken token: String?) -> String? {
        guard let token, !token.isEmpty,
              let payload = decodeJWT(token: token)
        else { return nil }

        let auth = payload["https://api.openai.com/auth"] as? [String: Any]
        if let nested = auth?["chatgpt_plan_type"] as? String, !nested.isEmpty {
            return nested
        }
        if let direct = payload["chatgpt_plan_type"] as? String, !direct.isEmpty {
            return direct
        }
        return nil
    }

    private static func decodeJWT(token: String) -> [String: Any]? {
        let parts = token.split(separator: ".", maxSplits: 2)
        guard parts.count == 3 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 {
            payload += "="
        }
        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return object
    }
}

struct CodexUsageResponse: Decodable {
    struct RateLimit: Decodable {
        struct Window: Decodable {
            let usedPercent: Int
            let resetAt: Int
            let limitWindowSeconds: Int

            enum CodingKeys: String, CodingKey {
                case usedPercent = "used_percent"
                case resetAt = "reset_at"
                case limitWindowSeconds = "limit_window_seconds"
            }
        }

        let primaryWindow: Window?
        let secondaryWindow: Window?

        enum CodingKeys: String, CodingKey {
            case primaryWindow = "primary_window"
            case secondaryWindow = "secondary_window"
        }
    }

    let planType: String?
    let rateLimit: RateLimit?

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
    }
}

struct CodexUsageResult {
    let snapshot: UsageSnapshot
    let planType: String?
}

struct ClaudeAuthResolution {
    let accessToken: String
    let sourceText: String
    let subscriptionType: String?
    let rateLimitTier: String?
}

struct ClaudeWebSessionResolution {
    let sessionKey: String
    let sourceText: String
}

enum ClaudeAPIError: LocalizedError {
    case missingCredentials
    case invalidToken
    case rateLimited(retryAfter: String?)
    case network(String)
    case badStatus(Int, String)
    case parse(String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "未找到 Claude Code 凭据。请先运行 claude auth login。"
        case .invalidToken:
            return "Claude token 已失效，请重新登录 Claude Code。"
        case .rateLimited:
            return "Claude 用量接口已限流，请稍后再刷新。"
        case let .network(message):
            return "Claude 网络请求失败: \(message)"
        case let .badStatus(code, body):
            return "Claude 接口返回 HTTP \(code): \(body)"
        case let .parse(message):
            return "Claude 解析失败: \(message)"
        }
    }
}

final class ClaudeCredentialsProvider {
    private enum KeychainReadResult {
        case success(Data)
        case failure(OSStatus)
    }

    private struct Envelope: Decodable {
        let claudeAiOauth: OAuthCredentials?
    }

    private struct OAuthCredentials: Decodable {
        let accessToken: String?
        let subscriptionType: String?
        let rateLimitTier: String?
    }

    func resolveCredentials() throws -> ClaudeAuthResolution {
        guard let data = readClaudeCodeCredentialsFromKeychain() else {
            throw ClaudeAPIError.missingCredentials
        }

        let decoder = JSONDecoder()
        let credentials: OAuthCredentials?
        if let envelope = try? decoder.decode(Envelope.self, from: data) {
            credentials = envelope.claudeAiOauth
        } else {
            credentials = try? decoder.decode(OAuthCredentials.self, from: data)
        }

        guard let oauth = credentials,
              let accessToken = oauth.accessToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              !accessToken.isEmpty
        else {
            throw ClaudeAPIError.missingCredentials
        }

        return ClaudeAuthResolution(
            accessToken: accessToken,
            sourceText: "钥匙串(Claude Code)",
            subscriptionType: oauth.subscriptionType,
            rateLimitTier: oauth.rateLimitTier)
    }

    private func readClaudeCodeCredentialsFromKeychain() -> Data? {
        switch readClaudeCodeCredentialsFromKeychain(allowsInteraction: false) {
        case let .success(data):
            return data
        case let .failure(status):
            for step in KeychainCredentialFallbackPolicy.nextSteps(after: status) {
                switch step {
                case .promptForDirectAppAccess:
                    if case let .success(data) = readClaudeCodeCredentialsFromKeychain(allowsInteraction: true) {
                        return data
                    }
                case .securityCLI:
                    if let data = readClaudeCodeCredentialsUsingSecurityCLI() {
                        return data
                    }
                }
            }
            return nil
        }
    }

    private func readClaudeCodeCredentialsFromKeychain(allowsInteraction: Bool) -> KeychainReadResult {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrLabel: "Claude Code-credentials",
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecAttrSynchronizable: kCFBooleanFalse as Any,
        ]

        if !allowsInteraction {
            let context = LAContext()
            context.interactionNotAllowed = true
            query[kSecUseAuthenticationContext] = context
        }

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data {
            return .success(data)
        }
        return .failure(status)
    }

    private func readClaudeCodeCredentialsUsingSecurityCLI() -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-l", "Claude Code-credentials", "-w"]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            finished.signal()
        }

        do {
            try process.run()
        } catch {
            return nil
        }

        if finished.wait(timeout: .now() + 5) == .timedOut {
            process.terminate()
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        return output.fileHandleForReading.readDataToEndOfFile()
    }
}

final class ClaudeWebSessionProvider {
    private let cookieClient = BrowserCookieClient()

    func resolveSession() -> ClaudeWebSessionResolution? {
        let query = BrowserCookieQuery(
            domains: ["claude.ai"],
            domainMatch: .suffix,
            includeExpired: false)

        for browser in Browser.defaultImportOrder {
            do {
                let stores = try cookieClient.records(matching: query, in: browser)
                for store in stores {
                    let cookies = store.cookies(origin: query.origin)
                    if let sessionKey = cookies.first(where: { $0.name == "sessionKey" })?.value,
                       sessionKey.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("sk-ant-")
                    {
                        return ClaudeWebSessionResolution(
                            sessionKey: sessionKey.trimmingCharacters(in: .whitespacesAndNewlines),
                            sourceText: "浏览器(\(store.label))")
                    }
                }
            } catch {
                continue
            }
        }

        return nil
    }
}

struct ClaudeUsageResult {
    let snapshot: UsageSnapshot
    let planType: String?
}

struct CursorAuthResolution {
    let accessToken: String
    let sourceText: String
}

enum CursorAPIError: LocalizedError {
    case missingCredentials
    case invalidToken
    case rateLimited
    case network(String)
    case badStatus(Int, String)
    case parse(String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "未找到 Cursor 凭据。请先登录 Cursor。"
        case .invalidToken:
            return "Cursor token 已失效，请重新登录 Cursor。"
        case .rateLimited:
            return "Cursor 用量接口已限流，请稍后再刷新。"
        case let .network(message):
            return "Cursor 网络请求失败: \(message)"
        case let .badStatus(code, body):
            return "Cursor 接口返回 HTTP \(code): \(body)"
        case let .parse(message):
            return "Cursor 解析失败: \(message)"
        }
    }
}

final class CursorCredentialsProvider {
    private enum KeychainReadResult {
        case success(String)
        case failure(OSStatus)
    }

    func resolveCredentials() throws -> CursorAuthResolution {
        guard let token = readCursorAccessTokenFromKeychain() else {
            throw CursorAPIError.missingCredentials
        }

        return CursorAuthResolution(
            accessToken: token,
            sourceText: "钥匙串(Cursor)")
    }

    private func readCursorAccessTokenFromKeychain() -> String? {
        switch readCursorAccessTokenFromKeychain(allowsInteraction: false) {
        case let .success(token):
            return token
        case let .failure(status):
            for step in KeychainCredentialFallbackPolicy.nextSteps(after: status) {
                switch step {
                case .promptForDirectAppAccess:
                    if case let .success(token) = readCursorAccessTokenFromKeychain(allowsInteraction: true) {
                        return token
                    }
                case .securityCLI:
                    if let token = readCursorAccessTokenUsingSecurityCLI() {
                        return token
                    }
                }
            }
            return nil
        }
    }

    private func readCursorAccessTokenFromKeychain(allowsInteraction: Bool) -> KeychainReadResult {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrLabel: "cursor-access-token",
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecAttrSynchronizable: kCFBooleanFalse as Any,
        ]

        if !allowsInteraction {
            let context = LAContext()
            context.interactionNotAllowed = true
            query[kSecUseAuthenticationContext] = context
        }

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess,
           let data = item as? Data,
           let token = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !token.isEmpty
        {
            return .success(token)
        }
        return .failure(status)
    }

    private func readCursorAccessTokenUsingSecurityCLI() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-l", "cursor-access-token", "-w"]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            finished.signal()
        }

        do {
            try process.run()
        } catch {
            return nil
        }

        if finished.wait(timeout: .now() + 5) == .timedOut {
            process.terminate()
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let token = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let token, !token.isEmpty else { return nil }
        return token
    }
}

struct CursorUsageResult {
    let snapshot: UsageSnapshot
    let planName: String?
}

private enum ClaudeWebUsageLoadResult {
    case loaded
    case unavailable
    case failed(String)
}

private enum ClaudeCLIUsageLoadResult {
    case loaded
    case unavailable
    case failed(String)
}

@MainActor
final class CodexAPIClient {
    func fetchUsage(with credentials: CodexAuthResolution) async throws -> CodexUsageResult {
        var request = URLRequest(url: codexUsageURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("VibeBar", forHTTPHeaderField: "User-Agent")
        if let accountId = credentials.accountId, !accountId.isEmpty {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw CodexAPIError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw CodexAPIError.network("无效 HTTP 响应")
        }

        if http.statusCode == 401 || http.statusCode == 403 {
            throw CodexAPIError.invalidToken
        }

        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            throw CodexAPIError.badStatus(http.statusCode, body)
        }

        let decoded: CodexUsageResponse
        do {
            decoded = try JSONDecoder().decode(CodexUsageResponse.self, from: data)
        } catch {
            throw CodexAPIError.parse(error.localizedDescription)
        }

        guard let primary = decoded.rateLimit?.primaryWindow else {
            throw CodexAPIError.parse("缺少 primary_window")
        }

        let primaryUsed = max(0, min(100, primary.usedPercent))
        let secondaryUsed = decoded.rateLimit?.secondaryWindow.map { max(0, min(100, $0.usedPercent)) }

        let snapshot = UsageSnapshot(
            weeklyUsed: primaryUsed,
            weeklyLimit: 100,
            weeklyRemaining: max(0, 100 - primaryUsed),
            weeklyResetAt: Date(timeIntervalSince1970: TimeInterval(primary.resetAt)),
            rateLimitUsed: secondaryUsed,
            rateLimitLimit: secondaryUsed == nil ? nil : 100,
            rateLimitRemaining: secondaryUsed.map { max(0, 100 - $0) },
            rateLimitResetAt: decoded.rateLimit?.secondaryWindow.map {
                Date(timeIntervalSince1970: TimeInterval($0.resetAt))
            },
            updatedAt: Date())

        return CodexUsageResult(snapshot: snapshot, planType: decoded.planType)
    }
}

@MainActor
final class ClaudeAPIClient {
    func fetchUsage(with credentials: ClaudeAuthResolution) async throws -> ClaudeUsageResult {
        var request = URLRequest(url: claudeUsageURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("VibeBar", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ClaudeAPIError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ClaudeAPIError.network("无效 HTTP 响应")
        }

        if http.statusCode == 401 || http.statusCode == 403 {
            throw ClaudeAPIError.invalidToken
        }
        if http.statusCode == 429 {
            throw ClaudeAPIError.rateLimited(retryAfter: http.value(forHTTPHeaderField: "Retry-After"))
        }

        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            throw ClaudeAPIError.badStatus(http.statusCode, body)
        }

        do {
            return ClaudeUsageResult(
                snapshot: try ClaudeUsageParser.snapshot(from: data),
                planType: credentials.subscriptionType)
        } catch {
            throw ClaudeAPIError.parse(error.localizedDescription)
        }
    }
}

@MainActor
final class ClaudeWebAPIClient {
    func fetchUsage(with session: ClaudeWebSessionResolution) async throws -> ClaudeUsageResult {
        do {
            let organizationData = try await fetchData(url: claudeWebOrganizationsURL, sessionKey: session.sessionKey)
            let organization = try ClaudeWebUsageParser.organization(from: organizationData)
            let usageURL = URL(string: "https://claude.ai/api/organizations/\(organization.id)/usage")!
            let usageData = try await fetchData(url: usageURL, sessionKey: session.sessionKey)
            return ClaudeUsageResult(
                snapshot: try ClaudeWebUsageParser.snapshot(from: usageData),
                planType: nil)
        } catch let error as ClaudeWebUsageFetchError {
            throw error
        } catch {
            throw ClaudeWebUsageFetchError.parse(error.localizedDescription)
        }
    }

    private func fetchData(url: URL, sessionKey: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("VibeBar", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ClaudeWebUsageFetchError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ClaudeWebUsageFetchError.network("无效 HTTP 响应")
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ClaudeWebUsageFetchError.badStatus(
                http.statusCode,
                isCloudflareChallenge: body.localizedCaseInsensitiveContains("Just a moment"))
        }
        return data
    }
}

private enum ClaudeCLIUsageClientError: LocalizedError {
    case missingBinary
    case probeDirectory(String)
    case launch(String)
    case timeout
    case parse(String)

    var errorDescription: String? {
        switch self {
        case .missingBinary:
            return "未找到 claude CLI。"
        case let .probeDirectory(message):
            return "无法创建 Claude CLI 探测目录：\(message)"
        case let .launch(message):
            return "无法启动 Claude CLI：\(message)"
        case .timeout:
            return "Claude CLI /usage 超时。"
        case let .parse(message):
            return "Claude CLI /usage 解析失败：\(message)"
        }
    }
}

private final class LockedProcessOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ newData: Data) {
        lock.lock()
        data.append(newData)
        lock.unlock()
    }

    func string() -> String {
        lock.lock()
        let snapshot = data
        lock.unlock()
        return String(data: snapshot, encoding: .utf8) ?? ""
    }
}

final class ClaudeCLIUsageClient: @unchecked Sendable {
    private let timeoutSeconds: TimeInterval

    init(timeoutSeconds: TimeInterval = 20) {
        self.timeoutSeconds = timeoutSeconds
    }

    func isAvailable() -> Bool {
        resolveClaudeBinary() != nil
    }

    func fetchUsage() async throws -> ClaudeUsageResult {
        guard let binaryURL = resolveClaudeBinary() else {
            throw ClaudeCLIUsageClientError.missingBinary
        }

        let output = try await captureUsageOutput(binaryURL: binaryURL)
        do {
            return ClaudeUsageResult(
                snapshot: try ClaudeCLIUsageParser.snapshot(from: output),
                planType: nil)
        } catch {
            throw ClaudeCLIUsageClientError.parse(error.localizedDescription)
        }
    }

    private func captureUsageOutput(binaryURL: URL) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        process.arguments = [
            "-q",
            "/dev/null",
            binaryURL.path,
            "--tools",
            "",
            "--permission-mode",
            "dontAsk",
            "--no-chrome",
        ]

        do {
            process.currentDirectoryURL = try probeDirectoryURL()
        } catch {
            throw ClaudeCLIUsageClientError.probeDirectory(error.localizedDescription)
        }

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let output = LockedProcessOutput()

        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                output.append(data)
            }
        }

        do {
            try process.run()
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            throw ClaudeCLIUsageClientError.launch(error.localizedDescription)
        }

        let deadline = Date().addingTimeInterval(timeoutSeconds)
        var sentUsageCommand = false
        var nextEnterAt = Date().addingTimeInterval(2.5)
        var lastParseError: Error?

        while Date() < deadline {
            let now = Date()
            if !sentUsageCommand, now >= nextEnterAt {
                write("/usage\r", to: inputPipe)
                sentUsageCommand = true
                nextEnterAt = now.addingTimeInterval(0.8)
            } else if sentUsageCommand, now >= nextEnterAt {
                write("\r", to: inputPipe)
                nextEnterAt = now.addingTimeInterval(0.8)
            }

            let currentOutput = output.string()
            do {
                _ = try ClaudeCLIUsageParser.snapshot(from: currentOutput)
                await stopProbe(
                    process: process,
                    inputPipe: inputPipe,
                    outputPipe: outputPipe,
                    sendExit: true)
                return currentOutput
            } catch {
                lastParseError = error
            }

            if !process.isRunning {
                break
            }

            try? await Task.sleep(nanoseconds: 250_000_000)
        }

        let exitedBeforeDeadline = !process.isRunning
        let finalOutput = output.string()
        await stopProbe(
            process: process,
            inputPipe: inputPipe,
            outputPipe: outputPipe,
            sendExit: false)

        if (try? ClaudeCLIUsageParser.snapshot(from: finalOutput)) != nil {
            return finalOutput
        }
        if exitedBeforeDeadline, let lastParseError {
            throw ClaudeCLIUsageClientError.parse(lastParseError.localizedDescription)
        }
        throw ClaudeCLIUsageClientError.timeout
    }

    private func stopProbe(
        process: Process,
        inputPipe: Pipe,
        outputPipe: Pipe,
        sendExit: Bool) async
    {
        if sendExit, process.isRunning {
            write("/exit\r", to: inputPipe)
            try? await Task.sleep(nanoseconds: 300_000_000)
        }

        if process.isRunning {
            process.terminate()
        }

        for _ in 0..<10 where process.isRunning {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        outputPipe.fileHandleForReading.readabilityHandler = nil
        try? inputPipe.fileHandleForWriting.close()
    }

    private func write(_ text: String, to pipe: Pipe) {
        do {
            try pipe.fileHandleForWriting.write(contentsOf: Data(text.utf8))
        } catch {
            // The probe may have exited between polling ticks.
        }
    }

    private func probeDirectoryURL() throws -> URL {
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
        let probeURL = baseURL
            .appendingPathComponent("VibeBar", isDirectory: true)
            .appendingPathComponent("ClaudeProbe", isDirectory: true)
        try FileManager.default.createDirectory(
            at: probeURL,
            withIntermediateDirectories: true)
        return probeURL
    }

    private func resolveClaudeBinary() -> URL? {
        var candidates: [String] = []
        if let override = ProcessInfo.processInfo.environment["CLAUDE_BIN"] {
            candidates.append(override)
        }

        let environmentPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for directory in environmentPath.split(separator: ":") {
            candidates.append(String(directory) + "/claude")
        }

        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        candidates.append(contentsOf: [
            "\(homePath)/.local/bin/claude",
            "\(homePath)/.claude/local/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "/usr/bin/claude",
        ])

        var seen = Set<String>()
        for candidate in candidates {
            let path = expandedPath(candidate)
            guard seen.insert(path).inserted else { continue }
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
               !isDirectory.boolValue,
               FileManager.default.isExecutableFile(atPath: path)
            {
                return URL(fileURLWithPath: path)
            }
        }

        return nil
    }

    private func expandedPath(_ path: String) -> String {
        if path == "~" {
            return FileManager.default.homeDirectoryForCurrentUser.path
        }
        if path.hasPrefix("~/") {
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(String(path.dropFirst(2)))
                .path
        }
        return path
    }
}

@MainActor
final class CursorAPIClient {
    func fetchUsage(with credentials: CursorAuthResolution) async throws -> CursorUsageResult {
        var request = URLRequest(url: cursorUsageURL)
        applyCursorHeaders(&request, credentials: credentials)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw CursorAPIError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw CursorAPIError.network("无效 HTTP 响应")
        }

        if http.statusCode == 401 || http.statusCode == 403 {
            throw CursorAPIError.invalidToken
        }
        if http.statusCode == 429 {
            throw CursorAPIError.rateLimited
        }

        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            throw CursorAPIError.badStatus(http.statusCode, body)
        }

        let snapshot: UsageSnapshot
        do {
            snapshot = try CursorUsageParser.snapshot(from: data)
        } catch {
            throw CursorAPIError.parse(error.localizedDescription)
        }

        let planName = await fetchPlanName(with: credentials)
        return CursorUsageResult(snapshot: snapshot, planName: planName)
    }

    private func fetchPlanName(with credentials: CursorAuthResolution) async -> String? {
        var request = URLRequest(url: cursorPlanInfoURL)
        applyCursorHeaders(&request, credentials: credentials)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            return try CursorUsageParser.planName(from: data)
        } catch {
            return nil
        }
    }

    private func applyCursorHeaders(_ request: inout URLRequest, credentials: CursorAuthResolution) {
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.httpBody = Data("{}".utf8)
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue("VibeBar", forHTTPHeaderField: "User-Agent")
    }
}

struct JWTSessionInfo {
    let deviceId: String?
    let sessionId: String?
    let trafficId: String?
}

@MainActor
final class KimiAPIClient {
    func fetchUsage(with token: String) async throws -> KimiUsageResult {
        let session = decodeJWTSessionInfo(token: token)
        var request = URLRequest(url: kimiUsageURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: ["scope": ["FEATURE_CODING"]])

        applyKimiCommonHeaders(&request, token: token, session: session)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw KimiAPIError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw KimiAPIError.network("无效 HTTP 响应")
        }

        if http.statusCode == 401 || http.statusCode == 403 {
            throw KimiAPIError.invalidToken
        }

        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            throw KimiAPIError.badStatus(http.statusCode, body)
        }

        let decoded: KimiUsageResponse
        do {
            decoded = try JSONDecoder().decode(KimiUsageResponse.self, from: data)
        } catch {
            throw KimiAPIError.parse(error.localizedDescription)
        }

        guard let coding = decoded.usages.first(where: { $0.scope == "FEATURE_CODING" }) else {
            throw KimiAPIError.parse("缺少 FEATURE_CODING scope")
        }

        let weekly = self.parseUsageNumbers(detail: coding.detail)

        let fiveHourRate = coding.limits?.first(where: {
            $0.window.duration == 300 && $0.window.timeUnit == "TIME_UNIT_MINUTE"
        }) ?? coding.limits?.first
        let rate = fiveHourRate.map { self.parseUsageNumbers(detail: $0.detail) }

        let snapshot = UsageSnapshot(
            weeklyUsed: weekly.used,
            weeklyLimit: weekly.limit,
            weeklyRemaining: weekly.remaining,
            weeklyResetAt: parseISO8601(coding.detail.resetTime),
            rateLimitUsed: rate?.used,
            rateLimitLimit: rate?.limit,
            rateLimitRemaining: rate?.remaining,
            rateLimitResetAt: parseISO8601(fiveHourRate?.detail.resetTime),
            updatedAt: Date())

        let planName = await fetchSubscriptionPlan(token: token, session: session)
        return KimiUsageResult(snapshot: snapshot, planName: planName)
    }

    private func fetchSubscriptionPlan(token: String, session: JWTSessionInfo?) async -> String? {
        let postBodies: [Data?] = [
            Data("{}".utf8),
            try? JSONSerialization.data(withJSONObject: ["scope": ["FEATURE_CODING"]]),
            nil,
        ]

        for body in postBodies {
            var request = URLRequest(url: kimiSubscriptionURL)
            request.httpMethod = "POST"
            request.timeoutInterval = 20
            request.httpBody = body
            applyKimiCommonHeaders(&request, token: token, session: session)
            if let plan = await requestPlan(with: request) {
                return plan
            }
        }

        var getRequest = URLRequest(url: kimiSubscriptionURL)
        getRequest.httpMethod = "GET"
        getRequest.timeoutInterval = 20
        applyKimiCommonHeaders(&getRequest, token: token, session: session)
        if let plan = await requestPlan(with: getRequest) {
            return plan
        }

        return parsePlanNameFromJWT(token: token)
    }

    private func requestPlan(with request: URLRequest) async -> String? {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            return parsePlanName(from: data)
        } catch {
            return nil
        }
    }

    private func parsePlanNameFromJWT(token: String) -> String? {
        let parts = token.split(separator: ".", maxSplits: 2)
        guard parts.count == 3 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 {
            payload += "="
        }
        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        let candidateKeys = [
            "plan_name",
            "planName",
            "subscription_name",
            "subscriptionName",
            "membership_level",
            "membershipLevel",
            "title",
        ]
        for key in candidateKeys {
            if let value = object[key] as? String,
               let normalized = normalizePlanCandidate(value)
            {
                return normalized
            }
        }
        return nil
    }

    private func applyKimiCommonHeaders(_ request: inout URLRequest, token: String, session: JWTSessionInfo?) {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("kimi-auth=\(token)", forHTTPHeaderField: "Cookie")
        request.setValue("https://www.kimi.com", forHTTPHeaderField: "Origin")
        request.setValue("https://www.kimi.com/code/console", forHTTPHeaderField: "Referer")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent")
        request.setValue("1", forHTTPHeaderField: "connect-protocol-version")
        request.setValue("en-US", forHTTPHeaderField: "x-language")
        request.setValue("web", forHTTPHeaderField: "x-msh-platform")
        request.setValue(TimeZone.current.identifier, forHTTPHeaderField: "r-timezone")

        if let session {
            if let deviceId = session.deviceId {
                request.setValue(deviceId, forHTTPHeaderField: "x-msh-device-id")
            }
            if let sessionId = session.sessionId {
                request.setValue(sessionId, forHTTPHeaderField: "x-msh-session-id")
            }
            if let trafficId = session.trafficId {
                request.setValue(trafficId, forHTTPHeaderField: "x-traffic-id")
            }
        }
    }

    private func parsePlanName(from data: Data) -> String? {
        if let decoded = try? JSONDecoder().decode(KimiSubscriptionResponse.self, from: data) {
            if let rawTitle = decoded.subscription?.goods?.title,
               let title = normalizePlanCandidate(rawTitle)
            {
                return title
            }
            if let rawTitle = decoded.purchaseSubscription?.goods?.title,
               let title = normalizePlanCandidate(rawTitle)
            {
                return title
            }
            if let rawLevel = decoded.subscription?.goods?.membershipLevel,
               let level = normalizeKimiLevel(rawLevel)
            {
                return level
            }
            if let rawLevel = decoded.purchaseSubscription?.goods?.membershipLevel,
               let level = normalizeKimiLevel(rawLevel)
            {
                return level
            }
            if let codingMembership = decoded.memberships?.first(where: { $0.feature == "FEATURE_CODING" }),
               let rawLevel = codingMembership.level,
               let level = normalizeKimiLevel(rawLevel)
            {
                return level
            }
        }

        if let object = try? JSONSerialization.jsonObject(with: data),
           let fromObject = findPlanName(in: object)
        {
            return fromObject
        }

        if let raw = String(data: data, encoding: .utf8) {
            return findPlanNameInRawText(raw)
        }
        return nil
    }

    private func findPlanName(in object: Any) -> String? {
        if let dict = object as? [String: Any] {
            let preferredKeys = [
                "plan_name",
                "planName",
                "subscription_name",
                "subscriptionName",
                "package_name",
                "packageName",
                "tier_name",
                "tierName",
                "product_name",
                "productName",
                "member_plan_name",
                "memberPlanName",
                "title",
                "name",
                "display_name",
                "displayName",
                "membership_level",
                "membershipLevel",
            ]
            for preferred in preferredKeys {
                if let value = dict[preferred] as? String,
                   let normalized = normalizePlanCandidate(value)
                {
                    return normalized
                }
            }

            for (key, value) in dict {
                let lowerKey = key.lowercased()
                if (lowerKey.contains("plan")
                    || lowerKey.contains("package")
                    || lowerKey.contains("tier")
                    || lowerKey.contains("product")),
                    let text = value as? String,
                    let normalized = normalizePlanCandidate(text)
                {
                    return normalized
                }
            }

            for value in dict.values {
                if let found = findPlanName(in: value) {
                    return found
                }
            }
        } else if let array = object as? [Any] {
            for item in array {
                if let found = findPlanName(in: item) {
                    return found
                }
            }
        }
        return nil
    }

    private func normalizePlanCandidate(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.count <= 40 else { return nil }
        guard !trimmed.lowercased().hasPrefix("http") else { return nil }
        guard UUID(uuidString: trimmed) == nil else { return nil }
        return trimmed
    }

    private func normalizeKimiLevel(_ raw: String) -> String? {
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "LEVEL_", with: "")
        guard !cleaned.isEmpty else { return nil }
        let words = cleaned.lowercased().split(separator: "_")
        guard !words.isEmpty else { return nil }
        return words
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private func findPlanNameInRawText(_ raw: String) -> String? {
        let patterns: [(String, Bool)] = [
            (#""goods"\s*:\s*\{[^}]*"title"\s*:\s*"([^"]+)""#, true),
            (#""purchaseSubscription"\s*:\s*\{[\s\S]*?"goods"\s*:\s*\{[^}]*"title"\s*:\s*"([^"]+)""#, true),
            (#""membershipLevel"\s*:\s*"(LEVEL_[A-Z_]+)""#, false),
        ]

        for (pattern, isTitle) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
            guard let match = regex.firstMatch(in: raw, options: [], range: range),
                  match.numberOfRanges > 1,
                  let capturedRange = Range(match.range(at: 1), in: raw)
            else {
                continue
            }

            let captured = String(raw[capturedRange])
            if isTitle, let title = normalizePlanCandidate(captured) {
                return title
            }
            if !isTitle, let level = normalizeKimiLevel(captured) {
                return level
            }
        }

        if let level = extractCodingMembershipLevelFromRawText(raw) {
            return level
        }
        return nil
    }

    private func extractCodingMembershipLevelFromRawText(_ raw: String) -> String? {
        let pattern =
            #""feature"\s*:\s*"FEATURE_CODING"[\s\S]*?"level"\s*:\s*"(LEVEL_[A-Z_]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        guard let match = regex.firstMatch(in: raw, options: [], range: range),
              match.numberOfRanges > 1,
              let capturedRange = Range(match.range(at: 1), in: raw)
        else {
            return nil
        }
        return normalizeKimiLevel(String(raw[capturedRange]))
    }

    private func parseISO8601(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let value = formatter.date(from: raw) {
            return value
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }

    private func parseUsageNumbers(detail: KimiUsageResponse.Usage.Detail) -> (used: Int, limit: Int, remaining: Int) {
        let limit = Int(detail.limit) ?? 0
        let rawUsed = Int(detail.used ?? "")
        let rawRemaining = Int(detail.remaining ?? "")

        let used: Int
        let remaining: Int

        if let rawUsed, let rawRemaining {
            used = rawUsed
            remaining = rawRemaining
        } else if let rawUsed {
            used = rawUsed
            remaining = max(0, limit - rawUsed)
        } else if let rawRemaining {
            used = max(0, limit - rawRemaining)
            remaining = rawRemaining
        } else {
            used = 0
            remaining = max(0, limit)
        }

        return (used: used, limit: limit, remaining: remaining)
    }

    private func decodeJWTSessionInfo(token: String) -> JWTSessionInfo? {
        let parts = token.split(separator: ".", maxSplits: 2)
        guard parts.count == 3 else { return nil }

        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 {
            payload += "="
        }

        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        return JWTSessionInfo(
            deviceId: object["device_id"] as? String,
            sessionId: object["ssid"] as? String,
            trafficId: object["sub"] as? String)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let kimiTokenProvider = KimiTokenProvider()
    private let kimiAPIClient = KimiAPIClient()
    private let codexCredentialsProvider = CodexCredentialsProvider()
    private let codexAPIClient = CodexAPIClient()
    private let claudeCredentialsProvider = ClaudeCredentialsProvider()
    private let claudeAPIClient = ClaudeAPIClient()
    private let claudeCLIUsageClient = ClaudeCLIUsageClient()
    private let claudeWebSessionProvider = ClaudeWebSessionProvider()
    private let claudeWebAPIClient = ClaudeWebAPIClient()
    private let cursorCredentialsProvider = CursorCredentialsProvider()
    private let cursorAPIClient = CursorAPIClient()

    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var refreshTask: Task<Void, Never>?
    private var timer: Timer?
    private var loadingTimer: Timer?
    private var isRefreshing = false
    private var loadingPulseOn = false

    private var selectedProvider: ProviderTab = .kimi

    private var kimiSnapshot: UsageSnapshot?
    private var kimiError: String?
    private var kimiTokenSourceText: String = "-"
    private var kimiPlanText: String?
    private var cachedKimiToken: TokenResolution?

    private var codexSnapshot: UsageSnapshot?
    private var codexError: String?
    private var codexTokenSourceText: String = "-"
    private var codexPlanText: String?
    private var cachedCodexCredentials: CodexAuthResolution?

    private var claudeSnapshot: UsageSnapshot?
    private var claudeError: String?
    private var claudeTokenSourceText: String = "-"
    private var claudePlanText: String?
    private var cachedClaudeCredentials: ClaudeAuthResolution?
    private var cachedClaudeUsageResult: ClaudeUsageResult?
    private var claudeUsageRefreshPolicy = UsageRefreshPolicy()

    private var cursorSnapshot: UsageSnapshot?
    private var cursorError: String?
    private var cursorTokenSourceText: String = "-"
    private var cursorPlanText: String?
    private var cachedCursorCredentials: CursorAuthResolution?

    private var refreshInterval: RefreshInterval = .fiveMinutes

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = ""
        statusItem.button?.imagePosition = .imageOnly
        updateTitle()

        menu = NSMenu()
        statusItem.menu = menu
        rebuildMenu()

        refreshUsage()
        configureRefreshTimer()
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        loadingTimer?.invalidate()
        refreshTask?.cancel()
    }

    private func refreshUsage(for provider: ProviderTab? = nil) {
        let target = provider ?? selectedProvider
        beginLoadingAnimation()
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            await self.loadUsage(for: target)
        }
    }

    private func loadUsage(for provider: ProviderTab) async {
        defer { endLoadingAnimation() }
        switch provider {
        case .kimi:
            await loadKimiUsage()
        case .codex:
            await loadCodexUsage()
        case .claude:
            await loadClaudeUsage()
        case .cursor:
            await loadCursorUsage()
        }
    }

    private func loadKimiUsage() async {
        do {
            let resolved: TokenResolution
            if let token = cachedKimiToken {
                resolved = token
            } else {
                let token = try kimiTokenProvider.resolveToken()
                cachedKimiToken = token
                resolved = token
            }
            kimiTokenSourceText = resolved.source.description

            do {
                let result = try await kimiAPIClient.fetchUsage(with: resolved.token)
                kimiSnapshot = result.snapshot
                kimiPlanText = cleanPlanText(result.planName)
                kimiError = nil
            } catch KimiAPIError.invalidToken {
                if let refreshed = kimiTokenProvider.refreshFromBrowser() {
                    cachedKimiToken = refreshed
                    kimiTokenSourceText = refreshed.source.description
                    let result = try await kimiAPIClient.fetchUsage(with: refreshed.token)
                    kimiSnapshot = result.snapshot
                    kimiPlanText = cleanPlanText(result.planName)
                    kimiError = nil
                } else {
                    cachedKimiToken = nil
                    throw KimiAPIError.invalidToken
                }
            }
        } catch {
            kimiError = error.localizedDescription
        }

        if selectedProvider == .kimi {
            updateTitle()
            rebuildMenu()
        }
    }

    private func loadCodexUsage() async {
        do {
            let resolved: CodexAuthResolution
            if let creds = cachedCodexCredentials {
                resolved = creds
            } else {
                let creds = try codexCredentialsProvider.resolveCredentials()
                cachedCodexCredentials = creds
                resolved = creds
            }
            codexTokenSourceText = resolved.sourceText

            do {
                let result = try await codexAPIClient.fetchUsage(with: resolved)
                codexSnapshot = result.snapshot
                codexPlanText = formatPlanText(result.planType ?? resolved.fallbackPlanType)
                codexError = nil
            } catch CodexAPIError.invalidToken {
                cachedCodexCredentials = nil
                let refreshed = try codexCredentialsProvider.resolveCredentials()
                cachedCodexCredentials = refreshed
                codexTokenSourceText = refreshed.sourceText
                let result = try await codexAPIClient.fetchUsage(with: refreshed)
                codexSnapshot = result.snapshot
                codexPlanText = formatPlanText(result.planType ?? refreshed.fallbackPlanType)
                codexError = nil
            }
        } catch {
            codexError = error.localizedDescription
        }

        if selectedProvider == .codex {
            updateTitle()
            rebuildMenu()
        }
    }

    private func loadClaudeUsage() async {
        do {
            let resolved: ClaudeAuthResolution
            if let creds = cachedClaudeCredentials {
                resolved = creds
            } else {
                let creds = try claudeCredentialsProvider.resolveCredentials()
                cachedClaudeCredentials = creds
                resolved = creds
            }
            claudeTokenSourceText = resolved.sourceText

            do {
                try await loadClaudeUsage(with: resolved)
            } catch ClaudeAPIError.invalidToken {
                cachedClaudeCredentials = nil
                let refreshed = try claudeCredentialsProvider.resolveCredentials()
                cachedClaudeCredentials = refreshed
                claudeTokenSourceText = refreshed.sourceText
                try await loadClaudeUsage(with: refreshed)
            }
        } catch ClaudeAPIError.rateLimited(let retryAfter) {
            claudeError = ClaudeAPIError.rateLimited(retryAfter: retryAfter).localizedDescription
        } catch {
            if !(await applyClaudeFallback(
                after: .oauthUnavailable,
                credentials: cachedClaudeCredentials,
                retryText: nil,
                initialFallbackFailures: ["Claude OAuth 失败：\(error.localizedDescription)"]))
            {
                claudeError = error.localizedDescription
            }
        }

        if selectedProvider == .claude {
            updateTitle()
            rebuildMenu()
        }
    }

    private func loadClaudeCLIUsageIfAvailable() async -> ClaudeCLIUsageLoadResult {
        guard claudeCLIUsageClient.isAvailable() else {
            return .unavailable
        }

        do {
            let result = try await claudeCLIUsageClient.fetchUsage()
            cachedClaudeUsageResult = result
            claudeUsageRefreshPolicy.recordSuccess(at: Date())
            claudeTokenSourceText = "Claude CLI (/usage)"
            applyClaudeUsageResult(result, credentials: nil, staleMessage: nil)
            return .loaded
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func loadClaudeWebUsage(with webSession: ClaudeWebSessionResolution) async -> ClaudeWebUsageLoadResult {
        do {
            let result = try await claudeWebAPIClient.fetchUsage(with: webSession)
            cachedClaudeUsageResult = result
            claudeUsageRefreshPolicy.recordSuccess(at: Date())
            claudeTokenSourceText = "Claude Web \(webSession.sourceText)"
            applyClaudeUsageResult(result, credentials: nil, staleMessage: nil)
            return .loaded
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func loadClaudeUsage(with credentials: ClaudeAuthResolution) async throws {
        let now = Date()
        if let cachedClaudeUsageResult,
           let skipReason = claudeUsageRefreshPolicy.skipReason(at: now, hasCachedSnapshot: true)
        {
            if case let .rateLimited(retryAt) = skipReason,
               await applyClaudeFallback(
                after: .oauthRateLimited,
                credentials: credentials,
                retryText: durationText(until: retryAt, from: now))
            {
                return
            }

            applyClaudeUsageResult(
                cachedClaudeUsageResult,
                credentials: credentials,
                staleMessage: staleClaudeUsageMessage(for: skipReason, now: now))
            return
        }

        do {
            let result = try await claudeAPIClient.fetchUsage(with: credentials)
            cachedClaudeUsageResult = result
            claudeUsageRefreshPolicy.recordSuccess(at: Date())
            applyClaudeUsageResult(result, credentials: credentials, staleMessage: nil)
        } catch ClaudeAPIError.rateLimited(let retryAfter) {
            let limitedAt = Date()
            let retryAt = claudeUsageRefreshPolicy.recordRateLimit(retryAfterHeader: retryAfter, at: limitedAt)
            if await applyClaudeFallback(
                after: .oauthRateLimited,
                credentials: credentials,
                retryText: durationText(until: retryAt, from: limitedAt))
            {
                return
            }
            throw ClaudeAPIError.rateLimited(retryAfter: retryAfter)
        }
    }

    private func applyClaudeFallback(
        after trigger: ClaudeUsageFallbackTrigger,
        credentials: ClaudeAuthResolution?,
        retryText: String?,
        initialFallbackFailures: [String] = [])
        async -> Bool
    {
        let webSession = claudeWebSessionProvider.resolveSession()
        let nextSources = ClaudeUsageFallbackPolicy.nextSources(
            after: trigger,
            hasClaudeCLI: claudeCLIUsageClient.isAvailable(),
            hasClaudeWebSession: webSession != nil,
            hasCachedOAuthSnapshot: cachedClaudeUsageResult != nil)
        var fallbackFailures = initialFallbackFailures

        for source in nextSources {
            switch source {
            case .claudeCLI:
                switch await loadClaudeCLIUsageIfAvailable() {
                case .loaded:
                    return true
                case .failed(let message):
                    fallbackFailures.append("Claude CLI fallback 失败：\(message)")
                case .unavailable:
                    break
                }
            case .claudeWebAPI:
                guard let webSession else { continue }
                switch await loadClaudeWebUsage(with: webSession) {
                case .loaded:
                    return true
                case .failed(let message):
                    fallbackFailures.append("Claude Web fallback 失败：\(message)")
                case .unavailable:
                    break
                }
            case .cachedOAuthSnapshot:
                if let cachedClaudeUsageResult {
                    applyClaudeUsageResult(
                        cachedClaudeUsageResult,
                        credentials: credentials,
                        staleMessage: claudeFallbackMessage(
                            after: trigger,
                            retryText: retryText,
                            fallbackFailures: fallbackFailures,
                            isShowingCachedData: true))
                    return true
                }
            }
        }

        if !fallbackFailures.isEmpty {
            claudeTokenSourceText = "Claude fallback"
            claudeError = claudeFallbackMessage(
                after: trigger,
                retryText: retryText,
                fallbackFailures: fallbackFailures,
                isShowingCachedData: false)
            return true
        }

        return false
    }

    private func claudeFallbackMessage(
        after trigger: ClaudeUsageFallbackTrigger,
        retryText: String?,
        fallbackFailures: [String],
        isShowingCachedData: Bool)
        -> String
    {
        switch trigger {
        case .oauthRateLimited:
            return ClaudeUsageFallbackPolicy.rateLimitedMessage(
                retryText: retryText,
                fallbackFailures: fallbackFailures,
                isShowingCachedData: isShowingCachedData)
        case .oauthUnavailable:
            let normalizedFailures = fallbackFailures
                .map(stripTrailingSentencePunctuation)
                .filter { !$0.isEmpty }
            var message = "Claude OAuth 不可用"
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
    }

    private func stripTrailingSentencePunctuation(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while result.last == "。" || result.last == "." {
            result.removeLast()
        }
        return result
    }

    private func applyClaudeUsageResult(
        _ result: ClaudeUsageResult,
        credentials: ClaudeAuthResolution?,
        staleMessage: String?)
    {
        claudeSnapshot = result.snapshot
        claudePlanText = formatPlanText(result.planType ?? credentials?.rateLimitTier)
        claudeError = staleMessage
    }

    private func staleClaudeUsageMessage(for reason: UsageRefreshSkipReason, now: Date) -> String? {
        switch reason {
        case .minimumInterval:
            return nil
        case .rateLimited(let retryAt):
            return "Claude 用量接口限流，显示缓存数据；约 \(durationText(until: retryAt, from: now)) 后重试。"
        }
    }

    private func durationText(until date: Date, from now: Date = Date()) -> String {
        let seconds = max(0, Int(ceil(date.timeIntervalSince(now))))
        if seconds == 0 {
            return "现在"
        }
        if seconds < 60 {
            return "\(seconds) 秒"
        }
        let minutes = Int(ceil(Double(seconds) / 60.0))
        return "\(minutes) 分钟"
    }

    private func loadCursorUsage() async {
        do {
            let resolved: CursorAuthResolution
            if let creds = cachedCursorCredentials {
                resolved = creds
            } else {
                let creds = try cursorCredentialsProvider.resolveCredentials()
                cachedCursorCredentials = creds
                resolved = creds
            }
            cursorTokenSourceText = resolved.sourceText

            do {
                let result = try await cursorAPIClient.fetchUsage(with: resolved)
                cursorSnapshot = result.snapshot
                cursorPlanText = formatPlanText(result.planName)
                cursorError = nil
            } catch CursorAPIError.invalidToken {
                cachedCursorCredentials = nil
                let refreshed = try cursorCredentialsProvider.resolveCredentials()
                cachedCursorCredentials = refreshed
                cursorTokenSourceText = refreshed.sourceText
                let result = try await cursorAPIClient.fetchUsage(with: refreshed)
                cursorSnapshot = result.snapshot
                cursorPlanText = formatPlanText(result.planName)
                cursorError = nil
            }
        } catch {
            cursorError = error.localizedDescription
        }

        if selectedProvider == .cursor {
            updateTitle()
            rebuildMenu()
        }
    }

    private func updateTitle() {
        let snapshot = self.activeSnapshot
        statusItem.button?.title = ""
        statusItem.button?.image = makeStatusIcon(snapshot: snapshot)
        statusItem.button?.toolTip = makeStatusTooltip(snapshot: snapshot)
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        menu.addItem(makeUsageCardItem())

        menu.addItem(.separator())
        menu.addItem(withTitle: "设置", action: nil, keyEquivalent: "")

        let refreshItem = NSMenuItem(title: "立即刷新", action: #selector(refreshNow), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let openTitle: String
        switch selectedProvider {
        case .kimi:
            openTitle = "打开 Kimi 控制台"
        case .codex:
            openTitle = "打开 Codex 用量页"
        case .claude:
            openTitle = "打开 Claude 用量页"
        case .cursor:
            openTitle = "打开 Cursor 用量页"
        }
        let openItem = NSMenuItem(title: openTitle, action: #selector(openProviderConsole), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)

        let intervalItem = NSMenuItem(title: "自动刷新频率", action: nil, keyEquivalent: "")
        intervalItem.submenu = makeRefreshIntervalSubmenu()
        menu.addItem(intervalItem)

        menu.addItem(withTitle: "当前频率: \(refreshInterval.title)", action: nil, keyEquivalent: "")

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "退出 VibeBar", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func refreshNow() {
        refreshUsage()
    }

    @objc private func selectRefreshInterval(_ sender: NSMenuItem) {
        guard let interval = RefreshInterval(rawValue: TimeInterval(sender.tag)) else { return }
        refreshInterval = interval
        configureRefreshTimer()
        rebuildMenu()
    }

    @objc private func openProviderConsole() {
        switch selectedProvider {
        case .kimi:
            NSWorkspace.shared.open(kimiConsoleURL)
        case .codex:
            NSWorkspace.shared.open(codexUsagePageURL)
        case .claude:
            NSWorkspace.shared.open(claudeUsagePageURL)
        case .cursor:
            NSWorkspace.shared.open(cursorUsagePageURL)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func configureRefreshTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval.rawValue, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshUsage()
            }
        }
    }

    private func beginLoadingAnimation() {
        isRefreshing = true
        loadingPulseOn = true
        loadingTimer?.invalidate()
        loadingTimer = Timer.scheduledTimer(withTimeInterval: 0.55, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.loadingPulseOn.toggle()
                self.updateTitle()
            }
        }
        updateTitle()
    }

    private func endLoadingAnimation() {
        isRefreshing = false
        loadingPulseOn = false
        loadingTimer?.invalidate()
        loadingTimer = nil
        updateTitle()
    }

    private func makeUsageCardItem() -> NSMenuItem {
        let snapshot = displaySnapshotForCurrentProvider()
        let view = UsageCardView(
            selectedProvider: selectedProvider,
            onSelectProvider: { [weak self] provider in
                Task { @MainActor [weak self] in
                    self?.switchProvider(provider)
                }
            },
            providerTitle: activeProviderTitle,
            planText: activePlanText,
            primaryTitle: activePrimaryTitle,
            secondaryTitle: activeSecondaryTitle,
            snapshot: snapshot,
            tokenSourceText: activeTokenSourceText,
            updatedText: snapshot.map { timeText($0.updatedAt) } ?? "-",
            weeklyResetText: snapshot?.weeklyResetAt.map(resetShortText) ?? "Resets -",
            rateResetText: snapshot?.rateLimitResetAt.map(resetShortText) ?? "Resets -",
            lastError: activeError)

        let hosting = NSHostingView(rootView: view)
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.layer?.isOpaque = false

        let width: CGFloat = 320
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: 1)
        hosting.layoutSubtreeIfNeeded()
        let height = max(1, hosting.fittingSize.height)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)

        let item = NSMenuItem()
        item.view = hosting
        return item
    }

    private func displaySnapshotForCurrentProvider() -> UsageSnapshot? {
        guard let snapshot = activeSnapshot else { return nil }
        guard selectedProvider == .kimi else { return snapshot }

        guard let sessionUsed = snapshot.rateLimitUsed,
              let sessionLimit = snapshot.rateLimitLimit
        else {
            return snapshot
        }

        let sessionRemaining = snapshot.rateLimitRemaining ?? max(0, sessionLimit - sessionUsed)

        return UsageSnapshot(
            weeklyUsed: sessionUsed,
            weeklyLimit: sessionLimit,
            weeklyRemaining: sessionRemaining,
            weeklyResetAt: snapshot.rateLimitResetAt,
            rateLimitUsed: snapshot.weeklyUsed,
            rateLimitLimit: snapshot.weeklyLimit,
            rateLimitRemaining: snapshot.weeklyRemaining,
            rateLimitResetAt: snapshot.weeklyResetAt,
            updatedAt: snapshot.updatedAt)
    }

    private func switchProvider(_ provider: ProviderTab) {
        guard selectedProvider != provider else { return }
        selectedProvider = provider
        updateTitle()
        rebuildMenu()
        refreshUsage(for: provider)
    }

    private var activeSnapshot: UsageSnapshot? {
        switch selectedProvider {
        case .kimi:
            kimiSnapshot
        case .codex:
            codexSnapshot
        case .claude:
            claudeSnapshot
        case .cursor:
            cursorSnapshot
        }
    }

    private var activeError: String? {
        switch selectedProvider {
        case .kimi:
            kimiError
        case .codex:
            codexError
        case .claude:
            claudeError
        case .cursor:
            cursorError
        }
    }

    private var activeTokenSourceText: String {
        switch selectedProvider {
        case .kimi:
            kimiTokenSourceText
        case .codex:
            codexTokenSourceText
        case .claude:
            claudeTokenSourceText
        case .cursor:
            cursorTokenSourceText
        }
    }

    private var activeProviderTitle: String {
        switch selectedProvider {
        case .kimi:
            "Kimi"
        case .codex:
            "Codex"
        case .claude:
            "Claude"
        case .cursor:
            "Cursor"
        }
    }

    private var activePlanText: String? {
        switch selectedProvider {
        case .kimi:
            kimiPlanText
        case .codex:
            codexPlanText
        case .claude:
            claudePlanText
        case .cursor:
            cursorPlanText
        }
    }

    private var activePrimaryTitle: String {
        switch selectedProvider {
        case .cursor:
            "Total"
        case .kimi, .codex, .claude:
            "Session"
        }
    }

    private var activeSecondaryTitle: String {
        switch selectedProvider {
        case .cursor:
            "API"
        case .kimi, .codex, .claude:
            "Weekly"
        }
    }

    private func makeRefreshIntervalSubmenu() -> NSMenu {
        let submenu = NSMenu()
        for option in RefreshInterval.allCases {
            let item = NSMenuItem(
                title: option.title,
                action: #selector(selectRefreshInterval(_:)),
                keyEquivalent: "")
            item.target = self
            item.tag = Int(option.rawValue)
            item.state = (option == refreshInterval) ? .on : .off
            submenu.addItem(item)
        }
        return submenu
    }

    private func resetShortText(_ date: Date) -> String {
        let seconds = Int(date.timeIntervalSinceNow)
        guard seconds > 0 else { return "Resets now" }

        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60

        var parts: [String] = []
        if days > 0 {
            parts.append("\(days)d")
            if hours > 0 {
                parts.append("\(hours)h")
            }
        } else if hours > 0 {
            parts.append("\(hours)h")
            if minutes > 0 {
                parts.append("\(minutes)m")
            }
        } else if minutes > 0 {
            parts.append("\(minutes)m")
        } else {
            return "Resets now"
        }

        return "Resets in \(parts.joined(separator: " "))"
    }

    private func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    private func formatPlanText(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else { return nil }
        let words = raw.replacingOccurrences(of: "_", with: " ")
        return words
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    private func cleanPlanText(_ raw: String?) -> String? {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else { return nil }
        return value
    }

    private func makeStatusIcon(snapshot: UsageSnapshot?) -> NSImage {
        let size = NSSize(width: 18, height: 14)
        let image = NSImage(size: size)
        image.lockFocus()
        defer {
            image.unlockFocus()
            image.isTemplate = true
        }

        let ink = NSColor.black
        let frame = NSRect(x: 0.5, y: 0.5, width: 17, height: 13)
        let border = NSBezierPath(roundedRect: frame, xRadius: 3, yRadius: 3)
        ink.withAlphaComponent(0.85).setStroke()
        border.lineWidth = 1
        border.stroke()

        func drawBar(y: CGFloat, progress: Double) {
            let track = NSRect(x: 2.2, y: y, width: 13.6, height: 2.1)
            let fillWidth = max(0, min(1, progress)) * track.width

            let trackPath = NSBezierPath(roundedRect: track, xRadius: 1.05, yRadius: 1.05)
            ink.withAlphaComponent(0.20).setFill()
            trackPath.fill()

            let fillRect = NSRect(x: track.minX, y: track.minY, width: fillWidth, height: track.height)
            let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: 1.05, yRadius: 1.05)
            ink.withAlphaComponent(0.95).setFill()
            fillPath.fill()
        }

        let hasError = (self.activeError?.isEmpty == false) && snapshot == nil
        if hasError {
            let x1 = NSBezierPath()
            x1.move(to: NSPoint(x: 6, y: 4))
            x1.line(to: NSPoint(x: 12, y: 10))
            x1.lineWidth = 1.6
            ink.withAlphaComponent(0.95).setStroke()
            x1.stroke()

            let x2 = NSBezierPath()
            x2.move(to: NSPoint(x: 12, y: 4))
            x2.line(to: NSPoint(x: 6, y: 10))
            x2.lineWidth = 1.6
            ink.withAlphaComponent(0.95).setStroke()
            x2.stroke()
        } else if let snapshot {
            let top = Double(snapshot.weeklyRemaining) / Double(max(1, snapshot.weeklyLimit))
            let bottom: Double
            if let r = snapshot.rateLimitRemaining, let l = snapshot.rateLimitLimit, l > 0 {
                bottom = Double(r) / Double(l)
            } else {
                bottom = top
            }
            drawBar(y: 8.2, progress: top)
            drawBar(y: 3.7, progress: bottom)
        } else {
            drawBar(y: 8.2, progress: 0.12)
            drawBar(y: 3.7, progress: 0.12)
        }

        if isRefreshing, loadingPulseOn {
            let dot = NSBezierPath(ovalIn: NSRect(x: 14.5, y: 10.4, width: 2.2, height: 2.2))
            ink.withAlphaComponent(0.95).setFill()
            dot.fill()
        }

        return image
    }

    private func makeStatusTooltip(snapshot: UsageSnapshot?) -> String {
        let providerName = activeProviderTitle
        guard let snapshot else {
            return "\(providerName)：暂无可用数据"
        }
        let primary = "\(snapshot.weeklyRemaining)/\(snapshot.weeklyLimit)"
        if let weeklyRemain = snapshot.rateLimitRemaining, let weeklyLimit = snapshot.rateLimitLimit {
            return "\(providerName) \(activePrimaryTitle) \(primary) · \(activeSecondaryTitle) \(weeklyRemain)/\(weeklyLimit)"
        }
        return "\(providerName) \(activePrimaryTitle) \(primary)"
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
