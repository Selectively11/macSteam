import XCTest
@testable import MacsteamApp

final class ConfigStoreReliabilityTests: XCTestCase {
    private var root: URL!
    private var configURL: URL!
    private var backupURL: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        configURL = root.appendingPathComponent("config.yaml")
        backupURL = root.appendingPathComponent("backups")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "HideWhatsNew: no\n".write(to: configURL, atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testFailedBackupPreventsOverwriteAndRollsBackVisibleState() throws {
        try "not a directory".write(to: backupURL, atomically: true, encoding: .utf8)
        let store = ConfigStore(configFile: configURL, backupDir: backupURL)
        store.load()

        XCTAssertThrowsError(try store.setHideWhatsNew(true))
        XCTAssertFalse(store.config.hideWhatsNew)
        XCTAssertEqual(try String(contentsOf: configURL, encoding: .utf8), "HideWhatsNew: no\n")
    }

    func testFailedAtomicWriteRollsBackVisibleStateAndPreservesFile() throws {
        enum InjectedFailure: Error { case write }
        let store = ConfigStore(configFile: configURL, backupDir: backupURL) { _, _ in
            throw InjectedFailure.write
        }
        store.load()

        XCTAssertThrowsError(try store.setHideWhatsNew(true))
        XCTAssertFalse(store.config.hideWhatsNew)
        XCTAssertEqual(try String(contentsOf: configURL, encoding: .utf8), "HideWhatsNew: no\n")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: backupURL.path).count, 1)
    }
}
