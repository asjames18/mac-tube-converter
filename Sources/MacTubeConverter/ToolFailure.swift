import Foundation

/// Keeps the last meaningful output lines of a tool so failures can explain themselves.
struct ToolOutputTail {
    private(set) var lines: [String] = []
    let limit: Int

    init(limit: Int = 12) { self.limit = limit }

    mutating func append(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !Self.isProgressNoise(trimmed) else { return }
        lines.append(trimmed)
        if lines.count > limit { lines.removeFirst(lines.count - limit) }
    }

    /// Error lines when present, otherwise the last few lines.
    var summary: String {
        let errors = lines.filter { $0.localizedCaseInsensitiveContains("error") }
        let chosen = errors.isEmpty ? Array(lines.suffix(3)) : Array(errors.suffix(3))
        return chosen.joined(separator: "\n")
    }

    static func isProgressNoise(_ line: String) -> Bool {
        if line.hasPrefix("[download]") && line.contains("%") { return true }
        if line.contains("whisper_print_progress_callback") { return true }
        if line.range(of: #"^[a-z_]+=\S*$"#, options: .regularExpression) != nil { return true } // ffmpeg -progress
        return false
    }
}

enum ToolFailure {
    private static let outdatedSignals = [
        "unable to extract", "nsig extraction failed", "sign in to confirm", "http error 403",
        "requested format is not available", "please report this issue", "confirm you're not a bot",
        "unsupported url", "signature extraction failed", "player response", "po token"
    ]

    /// Errors that are commonly fixed by updating yt-dlp.
    static func looksLikeOutdatedYtDlp(_ text: String) -> Bool {
        let lower = text.lowercased()
        return outdatedSignals.contains { lower.contains($0) }
    }
}
