import Foundation

public enum ClaudeWebUsageParserError: LocalizedError, Equatable {
    case missingOrganization

    public var errorDescription: String? {
        switch self {
        case .missingOrganization:
            return "Claude Web API 没有返回可用组织。"
        }
    }
}

public struct ClaudeWebOrganization: Equatable {
    public let id: String
    public let name: String?
}

public enum ClaudeWebUsageParser {
    private struct OrganizationResponse: Decodable {
        let uuid: String
        let name: String?
        let capabilities: [String]?

        var hasChatCapability: Bool {
            self.capabilities?.contains(where: { $0.localizedCaseInsensitiveContains("chat") }) ?? false
        }

        var isAPIOnly: Bool {
            guard let capabilities else { return false }
            return capabilities.contains(where: { $0.localizedCaseInsensitiveContains("api") })
                && !self.hasChatCapability
        }
    }

    public static func organization(from data: Data) throws -> ClaudeWebOrganization {
        let organizations = try JSONDecoder().decode([OrganizationResponse].self, from: data)
        let selected = organizations.first(where: { $0.hasChatCapability })
            ?? organizations.first(where: { !$0.isAPIOnly })
            ?? organizations.first
        guard let selected else {
            throw ClaudeWebUsageParserError.missingOrganization
        }

        let name = selected.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ClaudeWebOrganization(
            id: selected.uuid,
            name: name?.isEmpty == false ? name : nil)
    }

    public static func snapshot(from data: Data, updatedAt: Date = Date()) throws -> UsageSnapshot {
        try ClaudeUsageParser.snapshot(from: data, updatedAt: updatedAt)
    }
}
