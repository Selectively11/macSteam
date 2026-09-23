// Client version pin and repair
import Foundation

enum MacCrab {

    static let supportedVersion = "1788652215"

    static let localServerURL = "http://localhost:1666"

    enum Status: Equatable {
        case supported                 // already on the supported build
        case unsupported(String)       // on a different build (version shown)
        case unknown                   // manifest missing or unreadable
        case steamMissing              // inner client package dir absent
    }

    // MARK: - Detection

    static func status() -> Status {
        guard FileManager.default.fileExists(atPath: Paths.packageDir.path) else {
            return .steamMissing
        }
        guard let version = detectedVersion() else { return .unknown }
        return version == supportedVersion ? .supported : .unsupported(version)
    }

    static func detectedVersion() -> String? {
        let fm = FileManager.default
        let names = [
            "steam_client_osx.manifest",
            "steam_client_signed-2_osx.manifest",
            "steam_client_signed_osx.manifest",
        ]
        for name in names {
            let url = Paths.packageDir.appendingPathComponent(name)
            guard fm.fileExists(atPath: url.path),
                  let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            if let v = parseVersion(text) { return v }
        }
        if let entries = try? fm.contentsOfDirectory(atPath: Paths.packageDir.path) {
            for name in entries where name.hasPrefix("steam_client_") && name.hasSuffix(".manifest") {
                let url = Paths.packageDir.appendingPathComponent(name)
                if let text = try? String(contentsOf: url, encoding: .utf8),
                   let v = parseVersion(text) { return v }
            }
        }
        return nil
    }

    private static func parseVersion(_ text: String) -> String? {
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("\"version\"") else { continue }
            let quoted = trimmed.split(separator: "\"").map(String.init)
            if let value = quoted.last(where: { $0 != "version" && !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                let v = value.trimmingCharacters(in: .whitespaces)
                if v != "version" { return v }
            }
        }
        return nil
    }

    // MARK: - Full path (downgrade / repair)

    static func repair(progress: (@Sendable (String) -> Void)? = nil) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: Paths.steamAppExecutable.path) else {
            throw StepFailure(step: "Locate Steam", detail: "/Applications/Steam.app not found.")
        }
        guard fm.fileExists(atPath: Paths.packageDir.path) else {
            throw StepFailure(step: "Locate package",
                          detail: "The client package dir is missing. "
                                + "Open Steam once so it unbundles, then try again.")
        }
        try SteamInstaller.ensureModifiable()

        progress?("Stopping Steam")
        killSteam()

        progress?("Blocking update on launch")
        try SteamInstaller.writeUpdateBlock()

        try PackageFetcher.stageFromValve(progress: progress)

        progress?("Starting local package server")
        let server = PackageServer(root: Paths.packageDir)
        try server.start()
        defer { server.stop() }

        progress?("Running client update")
        let args = [
            "-forcesteamupdate",
            "-forcepackagedownload",
            "-overridepackageurl", localServerURL,
            "-exitsteam",
        ]
        // Exit code unreliable (-exitsteam gives 254); manifest version is the real signal.
        let result = runOuter(args)

        progress?("Verifying build")
        guard let version = detectedVersion() else {
            throw StepFailure(step: "Verify build",
                          detail: "Update ran (exit \(result.code)) but the client version "
                                + "couldn't be read afterward.")
        }
        if version != supportedVersion {
            throw StepFailure(step: "Verify build",
                          detail: "Update ran but the client is on \(version), not the "
                                + "supported \(supportedVersion).")
        }

        progress?("Done")
    }

    // MARK: - Stock repair (clean bundle + pinned build)

    static func repairToStock(progress: (@Sendable (String) -> Void)? = nil) throws {
        if steamIsRunning() {
            progress?("Quitting Steam so it can be repaired")
            killSteam()
        }

        try SteamBundleInstaller.downloadAndReplace(progress: progress)

        progress?("Unpacking the fresh client")
        _ = runOuter(["-exitsteam"])

        try repair(progress: progress)

        progress?("Steam has been repaired")
    }

    // MARK: - Uninstall (clean bundle, no pin)

    static func uninstallToStock(progress: (@Sendable (String) -> Void)? = nil) throws {
        if steamIsRunning() {
            progress?("Quitting Steam so it can be removed")
            killSteam()
        }

        try SteamBundleInstaller.downloadAndReplace(progress: progress)

        progress?("Clearing macSteam settings")
        try? SteamInstaller.disableUpdateBlock()

        progress?("macSteam has been removed")
    }

    // MARK: - Install preflight

    static func ensurePristineBundle(progress: (@Sendable (String) -> Void)? = nil) throws {
        if SteamBundleInstaller.isPristineValveBundle(Paths.steamApp) { return }
        if SteamBundleInstaller.hasLoadableInjectedLibraries(Paths.steamApp) { return }
        if steamIsRunning() {
            progress?("Quitting Steam")
            killSteam()
        }
        try SteamBundleInstaller.downloadAndReplace(progress: progress)
    }

    static func pinToSupported(progress: (@Sendable (String) -> Void)? = nil) throws {
        if !FileManager.default.fileExists(atPath: Paths.packageDir.path) {
            progress?("Unpacking the client")
            _ = runOuter(["-exitsteam"])
        }
        try repair(progress: progress)
    }

    // MARK: - Launch

    @discardableResult
    private static func runOuter(_ args: [String]) -> Subprocess.Result {
        Subprocess.run(Paths.steamAppExecutable.path, args)
    }

    private static func killSteam() {
        Subprocess.killSteam()
        Thread.sleep(forTimeInterval: 0.5)
    }

    private static func steamIsRunning() -> Bool {
        Subprocess.run("/usr/bin/pgrep", ["-x", "steam_osx"]).code == 0
    }
}
