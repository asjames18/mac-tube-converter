import Foundation

/// Finds yt-dlp, ffmpeg and whisper-cli. Copies bundled inside the app
/// (Contents/Resources/bin) always win; Homebrew/system copies are only a fallback for
/// developer builds. Set MACTUBE_BUNDLED_TOOLS_ONLY=1 to disable the fallback (clean-machine testing).
enum ToolLocator {
    static let bundledOnlyKey = "MACTUBE_BUNDLED_TOOLS_ONLY"
    static let systemDirectories = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]

    static func bundledDirectory(resourceURL: URL? = Bundle.main.resourceURL) -> URL? {
        resourceURL?.appendingPathComponent("bin", isDirectory: true)
    }

    static func bundledOnly(_ environment: [String: String]) -> Bool {
        environment[bundledOnlyKey] == "1"
    }

    /// Candidate paths in priority order: bundled copy, then Homebrew and system folders.
    static func candidates(named name: String, bundledDirectory: URL?,
                           environment: [String: String] = ProcessInfo.processInfo.environment) -> [String] {
        var paths: [String] = []
        if let bundledDirectory { paths.append(bundledDirectory.appendingPathComponent(name).path) }
        if !bundledOnly(environment) { paths += systemDirectories.map { "\($0)/\(name)" } }
        return paths
    }

    static func resolve(named name: String, bundledDirectory: URL?,
                        environment: [String: String] = ProcessInfo.processInfo.environment,
                        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> String? {
        candidates(named: name, bundledDirectory: bundledDirectory, environment: environment).first(where: isExecutable)
    }

    static func isBundled(_ path: String?, bundledDirectory: URL? = bundledDirectory()) -> Bool {
        guard let path, let bundledDirectory else { return false }
        return path.hasPrefix(bundledDirectory.path + "/")
    }

    /// PATH for child processes: the bundled folder first so tools find each other
    /// (yt-dlp looks for ffprobe next to ffmpeg and on PATH).
    static func searchPath(existing: String?, bundledDirectory: URL? = bundledDirectory(),
                           environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        var parts: [String] = []
        if let bundledDirectory { parts.append(bundledDirectory.path) }
        if !bundledOnly(environment) { parts += ["/opt/homebrew/bin", "/usr/local/bin"] }
        parts += ["/usr/bin", "/bin"]
        if !bundledOnly(environment), let existing, !existing.isEmpty { parts.append(existing) }
        return parts.joined(separator: ":")
    }

    /// yt-dlp needs a JavaScript runtime for YouTube. Point it at Deno (the bundled copy when present).
    static func jsRuntimeArguments(denoPath: String?) -> [String] {
        guard let denoPath, !denoPath.isEmpty else { return [] }
        return ["--js-runtimes", "deno:\(denoPath)"]
    }

    static func jsRuntimeArguments(environment: [String: String] = ProcessInfo.processInfo.environment) -> [String] {
        jsRuntimeArguments(denoPath: resolve(named: "deno", bundledDirectory: bundledDirectory(), environment: environment))
    }

    static func findExecutable(named name: String) async -> String? {
        let environment = ProcessInfo.processInfo.environment
        if let path = resolve(named: name, bundledDirectory: bundledDirectory(), environment: environment) { return path }
        guard !bundledOnly(environment) else { return nil }
        return await which(name)
    }

    private static func which(_ name: String) async -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", name]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return text?.isEmpty == false ? text : nil
        } catch {
            return nil
        }
    }
}
