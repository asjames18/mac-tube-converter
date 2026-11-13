import Foundation

struct ToolVersion: Equatable, Sendable {
    let installed: String?
    let latest: String?
    var isOutdated: Bool {
        guard let installed, let latest else { return false }
        return installed != latest
    }
}

/// Reads installed and latest Homebrew versions. Read-only: never installs or upgrades.
enum ToolVersions {
    static let formulae = ["yt-dlp": "yt-dlp", "ffmpeg": "ffmpeg", "whisper-cli": "whisper-cpp"]

    static func brewPath() -> String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func fetch() async -> [String: ToolVersion] {
        guard let brew = brewPath() else { return [:] }
        return await Task.detached(priority: .utility) { () -> [String: ToolVersion] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: brew)
            process.arguments = ["info", "--json=v2"] + formulae.values.sorted()
            var environment = ProcessInfo.processInfo.environment
            environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"
            environment["HOMEBREW_NO_ANALYTICS"] = "1"
            process.environment = environment
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice
            do { try process.run() } catch { return [:] }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return parse(data)
        }.value
    }

    static func parse(_ data: Data) -> [String: ToolVersion] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = root["formulae"] as? [[String: Any]] else { return [:] }
        var result: [String: ToolVersion] = [:]
        for formula in list {
            let name = formula["name"] as? String ?? ""
            let aliases = formula["aliases"] as? [String] ?? []
            guard let tool = formulae.first(where: { $0.value == name || aliases.contains($0.value) || $0.value.replacingOccurrences(of: "-", with: ".") == name })?.key else { continue }
            let latest = (formula["versions"] as? [String: Any])?["stable"] as? String
            let installed = (formula["installed"] as? [[String: Any]])?.last?["version"] as? String
            result[tool] = ToolVersion(installed: installed, latest: latest)
        }
        return result
    }
}
