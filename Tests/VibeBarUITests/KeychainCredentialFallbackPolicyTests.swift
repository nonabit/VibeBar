import Security
import Testing
import VibeBarUI

@Test
func promptsForDirectAppKeychainAccessBeforeUsingSecurityCLI() {
    let nextSteps = KeychainCredentialFallbackPolicy.nextSteps(after: errSecInteractionNotAllowed)

    #expect(nextSteps == [.promptForDirectAppAccess])
}

@Test
func doesNotShowSecondKeychainPromptAfterUserCancelsDirectAccess() {
    let nextSteps = KeychainCredentialFallbackPolicy.nextSteps(after: errSecUserCanceled)

    #expect(nextSteps.isEmpty)
}

@Test
func keepsSecurityCLIAsLastResortForNonAuthorizationFailures() {
    let nextSteps = KeychainCredentialFallbackPolicy.nextSteps(after: errSecItemNotFound)

    #expect(nextSteps == [.securityCLI])
}
