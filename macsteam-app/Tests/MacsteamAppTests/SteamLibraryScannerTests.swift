import XCTest
@testable import MacsteamApp

final class SteamLibraryScannerTests: XCTestCase {
    func testParsesModernLibraryFoldersAndDeduplicatesRoot() {
        let root = URL(fileURLWithPath: "/tmp/Steam")
        let text = #""libraryfolders" { "0" { "path" "/tmp/Steam" } "1" { "path" "/Volumes/Games" } }"#
        XCTAssertEqual(SteamLibraryScanner.parseLibraryFolders(text, steamRoot: root).map(\.path),
                       ["/tmp/Steam", "/Volumes/Games"])
    }

    func testParsesManifestMetadata() {
        let text = #""AppState" { "appid" "570" "name" "Dota 2" "installdir" "dota 2 beta" "SizeOnDisk" "1234" }"#
        let game = SteamLibraryScanner.parseManifest(text)
        XCTAssertEqual(game?.appID, 570)
        XCTAssertEqual(game?.title, "Dota 2")
        XCTAssertEqual(game?.size, 1234)
    }

    func testRejectsManifestTraversal() {
        let text = #""appid" "1" "name" "Bad" "installdir" "../outside""#
        XCTAssertNil(SteamLibraryScanner.parseManifest(text))
    }

    func testScanReturnsValidGamesAndPartialWarnings() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let steamapps = root.appendingPathComponent("steamapps")
        let install = steamapps.appendingPathComponent("common/Good Game")
        try FileManager.default.createDirectory(at: install.appendingPathComponent("Good.app"), withIntermediateDirectories: true)
        try #""AppState" { "appid" "42" "name" "Good Game" "installdir" "Good Game" "SizeOnDisk" "900" }"#
            .write(to: steamapps.appendingPathComponent("appmanifest_42.acf"), atomically: true, encoding: .utf8)
        try "garbage".write(to: steamapps.appendingPathComponent("appmanifest_bad.acf"), atomically: true, encoding: .utf8)
        let result = SteamLibraryScanner.scan(steamRoot: root)
        XCTAssertEqual(result.games.count, 1)
        XCTAssertEqual(result.games.first?.compatibility, .macOS)
        XCTAssertEqual(result.warnings.count, 1)
    }

    func testStaleDuplicateDoesNotHideValidInstallation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let second = root.appendingPathComponent("Second")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("steamapps"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second.appendingPathComponent("steamapps/common/Valid"), withIntermediateDirectories: true)
        let manifest = #""appid" "42" "name" "Valid" "installdir" "Valid""#
        try manifest.write(to: root.appendingPathComponent("steamapps/appmanifest_42.acf"), atomically: true, encoding: .utf8)
        try manifest.write(to: second.appendingPathComponent("steamapps/appmanifest_42.acf"), atomically: true, encoding: .utf8)
        let folders = #""libraryfolders" { "1" { "path" "\#(second.path)" } }"#
        try folders.write(to: root.appendingPathComponent("steamapps/libraryfolders.vdf"), atomically: true, encoding: .utf8)
        let result = SteamLibraryScanner.scan(steamRoot: root)
        XCTAssertEqual(result.games.map(\.title), ["Valid"])
    }
}
