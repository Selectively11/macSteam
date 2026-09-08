import XCTest
@testable import MacsteamApp

final class HealthDiagnosticsTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func testMissingSteamIsExplicit() {
        let health = HealthDiagnostics.inspect(environment(appExists: false))
        XCTAssertEqual(health.state, .missing)
    }

    func testUnsupportedBuildWinsClassification() throws {
        let env = environment(appExists: true, detected: "new", supported: "known")
        try createRequiredFiles(env)
        XCTAssertEqual(HealthDiagnostics.inspect(env).state, .unsupported)
    }

    func testVersionMismatchNeedsRepair() throws {
        let env = environment(appExists: true, detected: "known", supported: "known",
                              bundled: "2", installed: "1")
        try createRequiredFiles(env)
        XCTAssertEqual(HealthDiagnostics.inspect(env).state, .needsRepair)
    }

    func testHealthyState() throws {
        let env = environment(appExists: true, detected: "known", supported: "known",
                              bundled: "1", installed: "1")
        try createRequiredFiles(env)
        XCTAssertEqual(HealthDiagnostics.inspect(env).state, .healthy)
    }

    func testMissingManagedComponentIsMissing() throws {
        let env = environment(appExists: true, detected: "known", supported: "known", bundled: "1", installed: "1")
        try createRequiredFiles(env)
        try FileManager.default.removeItem(at: env.injectedDylib)
        XCTAssertEqual(HealthDiagnostics.inspect(env).state, .missing)
    }

    func testUnknownBuildNeedsRepair() throws {
        let env = environment(appExists: true, detected: nil, supported: "known", bundled: "1", installed: "1")
        try createRequiredFiles(env)
        XCTAssertEqual(HealthDiagnostics.inspect(env).state, .needsRepair)
    }

    func testIntelIsUnsupported() throws {
        let base = environment(appExists: true, detected: "known", supported: "known", bundled: "1", installed: "1")
        let env = HealthEnvironment(steamApp: base.steamApp, steamExecutable: base.steamExecutable,
            injectedDylib: base.injectedDylib, configFile: base.configFile, packageDirectory: base.packageDirectory,
            supportedBuild: base.supportedBuild, detectedBuild: base.detectedBuild, bundledVersion: base.bundledVersion,
            installedVersion: base.installedVersion, architecture: "Intel (x86_64)")
        try createRequiredFiles(env)
        XCTAssertEqual(HealthDiagnostics.inspect(env).state, .unsupported)
    }

    func testDetectsSteamInAlternateApplicationFolder() throws {
        let missing = root.appendingPathComponent("Missing.app")
        let alternate = root.appendingPathComponent("Applications/Steam.app")
        try FileManager.default.createDirectory(at: alternate, withIntermediateDirectories: true)
        XCTAssertEqual(Paths.detectSteamApp(candidates: [missing, alternate]).path, alternate.path)
    }

    func testRedactorRemovesPersonalAndAccountData() {
        let input = "/Users/alice/Library token=abc 76561191234567890 STEAM_0:1:123 password:hello"
        let result = DiagnosticRedactor.redact(input, home: URL(fileURLWithPath: "/Users/alice"))
        XCTAssertFalse(result.contains("alice"))
        XCTAssertFalse(result.contains("abc"))
        XCTAssertFalse(result.contains("7656119"))
        XCTAssertFalse(result.contains("STEAM_"))
        XCTAssertFalse(result.contains("hello"))
    }

    func testRedactorHandlesStructuredSecretsAndUnrelatedPaths() {
        let input = #"{"accountid":"123", "token" "secret value"} access_token=abc /Volumes/Private/User/save /tmp/person/file"#
        let result = DiagnosticRedactor.redact(input)
        for secret in ["123", "secret value", "abc", "/Volumes/Private", "/tmp/person"] {
            XCTAssertFalse(result.contains(secret), "Leaked \(secret)")
        }
    }

    private func environment(appExists: Bool, detected: String? = nil, supported: String = "known",
                             bundled: String? = nil, installed: String? = nil) -> HealthEnvironment {
        let app = root.appendingPathComponent(appExists ? "Steam.app" : "Missing.app")
        return HealthEnvironment(steamApp: app,
            steamExecutable: app.appendingPathComponent("Contents/MacOS/steam_osx"),
            injectedDylib: app.appendingPathComponent("Contents/MacOS/macsteam.dylib"),
            configFile: root.appendingPathComponent("config.yaml"),
            packageDirectory: root.appendingPathComponent("package"), supportedBuild: supported,
            detectedBuild: detected, bundledVersion: bundled, installedVersion: installed,
            architecture: "Apple silicon (arm64)")
    }

    private func createRequiredFiles(_ env: HealthEnvironment) throws {
        try FileManager.default.createDirectory(at: env.steamExecutable.deletingLastPathComponent(), withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.createFile(atPath: env.steamExecutable.path, contents: Data()))
        XCTAssertTrue(FileManager.default.createFile(atPath: env.injectedDylib.path, contents: Data()))
        XCTAssertTrue(FileManager.default.createFile(atPath: env.configFile.path, contents: Data()))
        try FileManager.default.createDirectory(at: env.packageDirectory, withIntermediateDirectories: true)
    }
}
