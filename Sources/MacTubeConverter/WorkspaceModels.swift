import Foundation

extension AppTab {
    var symbol: String {
        switch self {
        case .download: "arrow.down.circle"
        case .convert: "arrow.triangle.2.circlepath"
        case .transcribe: "waveform"
        }
    }
    var subtitle: String {
        switch self {
        case .download: "Save video and audio from a link."
        case .convert: "Your media, in the format you need."
        case .transcribe: "Turn spoken words into text and subtitles."
        }
    }
}

extension ConversionFormat {
    var detail: String {
        switch self {
        case .mp4: "H.264 video · easy to share"
        case .mov: "ProRes video · made for editing"
        case .mp3: "Audio · widely compatible"
        case .m4a: "AAC audio · compact files"
        case .wav: "Uncompressed audio · editing quality"
        }
    }
    var supportsQuality: Bool { self == .mp4 || self == .mp3 || self == .m4a }
}

extension DownloadFormat {
    var detail: String {
        switch self {
        case .mp4: "Video with audio"
        case .audioMP3: "Audio for any player"
        case .audioM4A: "Compact AAC audio"
        case .best: "Highest available quality"
        }
    }
}

enum ConversionQuality: String, CaseIterable, Identifiable {
    case compact, balanced, high
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var crf: String {
        switch self { case .compact: "28"; case .balanced: "23"; case .high: "18" }
    }
    var bitrate: String {
        switch self { case .compact: "128k"; case .balanced: "192k"; case .high: "320k" }
    }
}

struct JobResult: Identifiable {
    let id = UUID()
    let name: String
    let operation: String
    let output: URL?
    let message: String
    let date = Date()
}
