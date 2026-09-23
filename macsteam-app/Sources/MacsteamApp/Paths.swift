// Canonical filesystem locations shared by the dylib and this app.

import Foundation

enum Paths {
    static var configDir: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/Application Support/macsteam", isDirectory: true)
    }
    static var configFile: URL {
        configDir.appendingPathComponent("config.yaml")
    }

    static var configBackupDir: URL {
        configDir.appendingPathComponent("backups", isDirectory: true)
    }

    static var signaturesDir: URL {
        configDir.appendingPathComponent("signatures", isDirectory: true)
    }

    static var steamRoot: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/Application Support/Steam", isDirectory: true)
    }

    static var depotCache: URL {
        steamRoot.appendingPathComponent("depotcache", isDirectory: true)
    }

    static var steamApp: URL {
        detectSteamApp()
    }

    static func detectSteamApp(fileManager: FileManager = .default,
                               candidates: [URL]? = nil) -> URL {
        let choices = candidates ?? [
            URL(fileURLWithPath: "/Applications/Steam.app", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications/Steam.app", isDirectory: true),
        ]
        return choices.first(where: { fileManager.fileExists(atPath: $0.path) }) ?? choices[0]
    }
    static var steamAppExecutable: URL {
        steamApp.appendingPathComponent("Contents/MacOS/steam_osx")
    }
    static var steamAppInfoPlist: URL {
        steamApp.appendingPathComponent("Contents/Info.plist")
    }
    static var steamAppInjectedDylib: URL {
        steamApp.appendingPathComponent("Contents/MacOS/macsteam.dylib")
    }

    static var innerClientMacOS: URL {
        steamRoot.appendingPathComponent("Steam.AppBundle/Steam/Contents/MacOS", isDirectory: true)
    }

    static var packageDir: URL {
        innerClientMacOS.appendingPathComponent("package", isDirectory: true)
    }

    static var steamCfgRoot: URL {
        steamRoot.appendingPathComponent("steam.cfg")
    }
    static var steamCfgInner: URL {
        innerClientMacOS.appendingPathComponent("steam.cfg")
    }

    static let defaultInjectionPackage = 20200

    static func ensureDir(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
