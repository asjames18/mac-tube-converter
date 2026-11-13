import Foundation

enum WhisperModelCatalog {
    static let preferredNames = ["ggml-small.en-q5_1.bin", "ggml-large-v3-turbo-q5_0.bin", "ggml-small.en.bin", "ggml-base.en.bin"]

    /// Model folders in priority order: MACTUBE_MODEL_DIR, Application Support, then the
    /// workspace's sibling Models folder. Models are never copied or moved.
    static func searchFolders(environment: [String: String] = ProcessInfo.processInfo.environment,
                              home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        var folders: [URL] = []
        if let custom = environment["MACTUBE_MODEL_DIR"], !custom.isEmpty {
            folders.append(URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true))
        }
        folders.append(home.appendingPathComponent("Library/Application Support/MacTubeConverter/Models", isDirectory: true))
        folders.append(home.appendingPathComponent("Documents/Mac Apps/Models", isDirectory: true))
        // Builds before 1.2 bundled models inside the app; still honour them if present.
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Models", isDirectory: true) { folders.append(bundled) }
        return folders
    }

    /// Lists readable ggml-*.bin files in the given folders only (never arbitrary directories).
    /// A file name found in an earlier folder wins.
    static func find(in folders: [URL]) -> [URL] {
        var seen = Set<String>()
        var found: [URL] = []
        for folder in folders {
            let names = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
            for name in names where name.hasPrefix("ggml-") && name.hasSuffix(".bin") && !seen.contains(name) {
                let url = folder.appendingPathComponent(name)
                guard FileManager.default.isReadableFile(atPath: url.path) else { continue }
                seen.insert(name)
                found.append(url)
            }
        }
        return found.sorted { rank($0) < rank($1) }
    }

    private static func rank(_ url: URL) -> Int {
        preferredNames.firstIndex(of: url.lastPathComponent) ?? preferredNames.count
    }
}
