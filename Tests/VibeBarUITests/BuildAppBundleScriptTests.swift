import Foundation
import Testing

@Test
func buildAppBundleScriptSupportsConfigurableCodeSigningIdentity() throws {
    let script = try String(contentsOfFile: repositoryPath("scripts/build_app_bundle.sh"), encoding: .utf8)

    #expect(script.contains("CODE_SIGN_IDENTITY"))
    #expect(script.contains("codesign"))
}

@Test
func buildAppBundleScriptSignsTheAppBundleIdentifier() throws {
    let script = try String(contentsOfFile: repositoryPath("scripts/build_app_bundle.sh"), encoding: .utf8)

    #expect(script.contains("--identifier \"$BUNDLE_ID\""))
}

@Test
func releaseWorkflowImportsCertificateAndVerifiesSignedApp() throws {
    let workflow = try String(contentsOfFile: repositoryPath(".github/workflows/release.yml"), encoding: .utf8)

    #expect(workflow.contains("MACOS_CERTIFICATE_P12_BASE64"))
    #expect(workflow.contains("security import"))
    #expect(workflow.contains("codesign --verify --deep --strict"))
}

private func repositoryPath(_ relativePath: String) -> String {
    let testFile = URL(fileURLWithPath: #filePath)
    return testFile
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent(relativePath)
        .path
}
