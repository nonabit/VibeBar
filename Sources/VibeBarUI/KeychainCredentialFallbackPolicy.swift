import Security

public enum KeychainCredentialFallbackStep: Equatable {
    case promptForDirectAppAccess
    case securityCLI
}

public enum KeychainCredentialFallbackPolicy {
    public static func nextSteps(after status: OSStatus) -> [KeychainCredentialFallbackStep] {
        switch status {
        case errSecInteractionNotAllowed:
            return [.promptForDirectAppAccess]
        case errSecUserCanceled, errSecAuthFailed:
            return []
        default:
            return [.securityCLI]
        }
    }
}
