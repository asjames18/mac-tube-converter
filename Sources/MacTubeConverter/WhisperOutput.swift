import Foundation

/// Decode after a whole line arrives so pipe boundaries cannot split UTF-8 characters.
struct ProcessLineDecoder {
    private var pending = Data()

    mutating func append(_ data: Data) -> [String] {
        pending.append(data)
        var lines: [String] = []
        while let end = pending.firstIndex(where: { $0 == 10 || $0 == 13 }) {
            let line = String(decoding: pending[..<end], as: UTF8.self)
            pending.removeSubrange(...end)
            if !line.isEmpty { lines.append(line) }
        }
        return lines
    }

    mutating func finish() -> [String] {
        defer { pending.removeAll() }
        return pending.isEmpty ? [] : [String(decoding: pending, as: UTF8.self)]
    }
}

enum WhisperOutput {
    struct Segment { let text: String; let endSeconds: Double }

    static func progress(in line: String) -> Double? {
        guard line.contains("whisper_print_progress_callback"),
              let start = line.range(of: "progress ="), let end = line[start.upperBound...].firstIndex(of: "%"),
              let value = Double(line[start.upperBound..<end].trimmingCharacters(in: .whitespaces)),
              (0...100).contains(value) else { return nil }
        return value / 100
    }

    static func segment(in line: String) -> Segment? {
        guard line.hasPrefix("["), let arrow = line.range(of: " --> "),
              let close = line[arrow.upperBound...].firstIndex(of: "]") else { return nil }
        let components = line[arrow.upperBound..<close].split(separator: ":").compactMap { Double($0) }
        guard components.count == 3 else { return nil }
        let text = line[line.index(after: close)...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return Segment(text: text, endSeconds: components[0] * 3600 + components[1] * 60 + components[2])
    }
}
