import Foundation

/// Removes leftovers of an interrupted job. Only files created during the job are touched,
/// and they go to the Trash so nothing is lost irreversibly.
enum PartialFiles {
    static func snapshot(_ folder: URL) -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
    }

    static func isDownloadLeftover(_ name: String) -> Bool {
        let lower = name.lowercased()
        if lower.hasSuffix(".part") || lower.hasSuffix(".ytdl") || lower.contains(".part-frag") || lower.hasSuffix(".temp") { return true }
        // Unmerged format streams such as "Title [id].f137.mp4".
        return lower.range(of: #"\.f[0-9]+(-[0-9]+)?\.[a-z0-9]+$"#, options: .regularExpression) != nil
    }

    /// Returns the names that were cleaned up.
    @discardableResult
    static func cleanDownloadLeftovers(in folder: URL, existingBefore: Set<String>) -> [String] {
        let created = snapshot(folder).subtracting(existingBefore).filter(isDownloadLeftover)
        for name in created { discard(folder.appendingPathComponent(name)) }
        return created.sorted()
    }

    static func discard(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        // Scratch files in the temporary directory are not user files; delete them outright.
        if url.standardizedFileURL.path.hasPrefix(FileManager.default.temporaryDirectory.standardizedFileURL.path) {
            try? FileManager.default.removeItem(at: url)
            return
        }
        do { try FileManager.default.trashItem(at: url, resultingItemURL: nil) }
        catch { try? FileManager.default.removeItem(at: url) }
    }
}
