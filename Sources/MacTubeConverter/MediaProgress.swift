import Foundation

/// Parses progress lines printed by yt-dlp (--newline) and ffmpeg (-progress pipe:1).
enum MediaProgress {
    static func ytDlpPercent(in line: String) -> Double? {
        guard line.hasPrefix("[download]"),
              let match = line.range(of: #"[0-9]+(\.[0-9]+)?%"#, options: .regularExpression),
              let value = Double(line[match].dropLast()), (0...100).contains(value) else { return nil }
        return value / 100
    }

    /// "  Duration: 00:01:02.50, start: 0.000000, bitrate: ..." → 62.5
    static func ffmpegDuration(in line: String) -> Double? {
        guard let range = line.range(of: "Duration: ") else { return nil }
        return clockSeconds(String(line[range.upperBound...].prefix(11)))
    }

    /// "out_time_us=12500000" → 12.5
    static func ffmpegOutTime(in line: String) -> Double? {
        guard line.hasPrefix("out_time_us="), let micro = Double(line.dropFirst("out_time_us=".count)), micro >= 0 else { return nil }
        return micro / 1_000_000
    }

    static func clockSeconds(_ text: String) -> Double? {
        let parts = text.split(separator: ":").compactMap { Double($0) }
        guard parts.count == 3 else { return nil }
        return parts[0] * 3600 + parts[1] * 60 + parts[2]
    }
}
