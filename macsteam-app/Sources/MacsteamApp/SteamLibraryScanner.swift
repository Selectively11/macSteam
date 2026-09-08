import Foundation

enum GameCompatibility: String, Equatable, Sendable {
    case macOS = "macOS app found"
    case unknown = "Not verifiable locally"
}

struct InstalledGame: Equatable, Sendable {
    let appID: Int
    let title: String
    let installDirectory: URL
    let libraryLabel: String
    let sizeOnDisk: Int64?
    let compatibility: GameCompatibility
}

struct LibraryScanResult: Equatable, Sendable {
    let games: [InstalledGame]
    let warnings: [String]
}

enum SteamLibraryScanner {
    static func parseLibraryFolders(_ text: String, steamRoot: URL) -> [URL] {
        let expression = try! NSRegularExpression(pattern: #"(?i)\"path\"\s+\"((?:\\.|[^\"])*)\""#)
        let ns = text as NSString
        var paths = [steamRoot]
        for match in expression.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let encoded = ns.substring(with: match.range(at: 1))
            let path = encoded.replacingOccurrences(of: #"\\"#, with: #"\"#)
            let url = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
            if !paths.contains(where: { $0.standardizedFileURL.path == url.path }) { paths.append(url) }
        }
        return paths
    }

    static func parseManifest(_ text: String) -> (appID: Int, title: String, installDir: String, size: Int64?)? {
        var values: [String: String] = [:]
        let expression = try! NSRegularExpression(pattern: #"\"([^\"]+)\"\s+\"([^\"]*)\""#)
        let ns = text as NSString
        for match in expression.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            values[ns.substring(with: match.range(at: 1)).lowercased()] = ns.substring(with: match.range(at: 2))
        }
        guard let idText = values["appid"], let appID = Int(idText), appID > 0,
              let title = values["name"]?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty,
              let directory = values["installdir"], isSafeComponent(directory) else { return nil }
        return (appID, title, directory, values["sizeondisk"].flatMap(Int64.init))
    }

    static func scan(steamRoot: URL = Paths.steamRoot,
                     fileManager: FileManager = .default) -> LibraryScanResult {
        let folderFile = steamRoot.appendingPathComponent("steamapps/libraryfolders.vdf")
        let libraries: [URL]
        if let text = try? String(contentsOf: folderFile, encoding: .utf8) {
            libraries = parseLibraryFolders(text, steamRoot: steamRoot)
        } else {
            libraries = [steamRoot]
        }
        var games: [InstalledGame] = []
        var warnings: [String] = []
        var seen = Set<Int>()
        for (index, library) in libraries.enumerated() {
            let steamapps = library.appendingPathComponent("steamapps", isDirectory: true)
            guard let manifests = try? fileManager.contentsOfDirectory(at: steamapps,
                includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
                warnings.append("Library \(index + 1) could not be read.")
                continue
            }
            for manifestURL in manifests where manifestURL.lastPathComponent.hasPrefix("appmanifest_") && manifestURL.pathExtension == "acf" {
                guard let text = try? String(contentsOf: manifestURL, encoding: .utf8),
                      let manifest = parseManifest(text) else {
                    warnings.append("One manifest in Library \(index + 1) was invalid.")
                    continue
                }
                guard !seen.contains(manifest.appID) else { continue }
                let common = steamapps.appendingPathComponent("common", isDirectory: true).standardizedFileURL
                let install = common.appendingPathComponent(manifest.installDir, isDirectory: true).standardizedFileURL
                guard install.path.hasPrefix(common.path + "/"), fileManager.fileExists(atPath: install.path) else {
                    warnings.append("\(manifest.title) has a manifest but no install folder.")
                    continue
                }
                seen.insert(manifest.appID)
                games.append(InstalledGame(appID: manifest.appID, title: manifest.title,
                    installDirectory: install, libraryLabel: "Library \(index + 1)",
                    sizeOnDisk: manifest.size, compatibility: compatibility(at: install, fileManager: fileManager)))
            }
        }
        return LibraryScanResult(games: games.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending },
                                 warnings: warnings)
    }

    private static func isSafeComponent(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." && !value.contains("/") && !value.contains("\\")
    }

    private static func compatibility(at directory: URL, fileManager: FileManager) -> GameCompatibility {
        guard let entries = try? fileManager.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return .unknown }
        return entries.contains(where: { $0.pathExtension.lowercased() == "app" }) ? .macOS : .unknown
    }
}
