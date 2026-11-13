import Foundation

enum OutputFiles {
    static func validWebURL(_ value: String) -> Bool {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty else { return false }
        return true
    }

    static func availableURL(in folder: URL, name: String, extension suffix: String) -> URL {
        var candidate = folder.appendingPathComponent(name).appendingPathExtension(suffix)
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(name) (\(number))").appendingPathExtension(suffix)
            number += 1
        }
        return candidate
    }

    /// Makes a title safe for a macOS file name.
    static func safeFileName(_ raw: String) -> String {
        let cleaned = raw.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        return cleaned.isEmpty ? "transcript" : String(cleaned.prefix(150))
    }

    /// "Talk Title [dQw4w9WgXcQ]" → "Talk Title"
    static func videoTitle(fromDownloadedName name: String) -> String {
        let title = name.replacingOccurrences(of: #"\s*\[[A-Za-z0-9_-]+\]$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? name : title
    }
}
