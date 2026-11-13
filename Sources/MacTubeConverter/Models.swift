import Foundation

enum AppTab: String, CaseIterable, Identifiable {
    case download
    case convert
    case transcribe

    var id: String { rawValue }

    var title: String {
        switch self {
        case .download: "Download"
        case .convert: "Convert"
        case .transcribe: "Transcribe"
        }
    }
}

enum DownloadFormat: String, CaseIterable, Identifiable {
    case mp4
    case audioMP3
    case audioM4A
    case best

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mp4: "MP4 Video"
        case .audioMP3: "MP3 Audio"
        case .audioM4A: "M4A Audio"
        case .best: "Best Original"
        }
    }

    var arguments: [String] {
        switch self {
        case .mp4:
            ["-f", "bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]/best", "--merge-output-format", "mp4"]
        case .audioMP3:
            ["-x", "--audio-format", "mp3", "--audio-quality", "0"]
        case .audioM4A:
            ["-x", "--audio-format", "m4a", "--audio-quality", "0"]
        case .best:
            []
        }
    }
}

enum ConversionFormat: String, CaseIterable, Identifiable {
    case mp4
    case mov
    case mp3
    case m4a
    case wav

    var id: String { rawValue }
    var fileExtension: String { rawValue }
    var title: String { rawValue.uppercased() }

    func arguments(input: URL, output: URL, quality: ConversionQuality = .balanced) -> [String] {
        let inputPath = input.path(percentEncoded: false)
        let outputPath = output.path(percentEncoded: false)

        switch self {
        case .mp4:
            return ["-nostdin", "-hide_banner", "-nostats", "-progress", "pipe:1", "-n", "-i", inputPath, "-c:v", "libx264", "-crf", quality.crf, "-c:a", "aac", "-movflags", "+faststart", outputPath]
        case .mov:
            return ["-nostdin", "-hide_banner", "-nostats", "-progress", "pipe:1", "-n", "-i", inputPath, "-c:v", "prores_ks", "-c:a", "pcm_s16le", outputPath]
        case .mp3:
            return ["-nostdin", "-hide_banner", "-nostats", "-progress", "pipe:1", "-n", "-i", inputPath, "-vn", "-b:a", quality.bitrate, outputPath]
        case .m4a:
            return ["-nostdin", "-hide_banner", "-nostats", "-progress", "pipe:1", "-n", "-i", inputPath, "-vn", "-c:a", "aac", "-b:a", quality.bitrate, outputPath]
        case .wav:
            return ["-nostdin", "-hide_banner", "-nostats", "-progress", "pipe:1", "-n", "-i", inputPath, "-vn", "-c:a", "pcm_s16le", outputPath]
        }
    }
}

enum TranscriptionSource: String, CaseIterable, Identifiable {
    case url
    case file

    var id: String { rawValue }
    var title: String { self == .url ? "YouTube URL" : "Local File" }
}

struct TranscriptionLanguage: Identifiable, Hashable {
    let id: String
    let title: String

    static let supported = [
        TranscriptionLanguage(id: "en", title: "English"),
        TranscriptionLanguage(id: "auto", title: "Auto Detect"),
        TranscriptionLanguage(id: "es", title: "Spanish"),
        TranscriptionLanguage(id: "fr", title: "French"),
        TranscriptionLanguage(id: "de", title: "German"),
        TranscriptionLanguage(id: "pt", title: "Portuguese"),
        TranscriptionLanguage(id: "it", title: "Italian")
    ]

    static func saved() -> TranscriptionLanguage {
        let id = UserDefaults.standard.string(forKey: "transcriptionLanguage")
        return supported.first { $0.id == id } ?? supported[0]
    }
}

struct ToolStatus: Identifiable {
    let name: String
    let path: String?
    let isRequired: Bool

    var id: String { name }
    var isAvailable: Bool { path != nil }

    var message: String {
        if let path {
            "\(name): \(path)"
        } else {
            "\(name): missing"
        }
    }
}

enum AppError: LocalizedError {
    case missingInput
    case missingTool(String)
    case missingModel
    case missingTranscriptionAudio
    /// Tool name, exit code, and the tool's last error lines.
    case processFailed(String, Int32, String)
    case emptyTranscript
    case outputMissing(String)

    var errorDescription: String? {
        switch self {
        case .missingInput:
            "Choose a file or enter a URL first."
        case .missingTool(let name):
            "\(name) is required."
        case .missingModel:
            "Whisper model not found. Put a ggml-*.bin model in ~/Library/Application Support/MacTubeConverter/Models (or set MACTUBE_MODEL_DIR), or choose a model file in Tools."
        case .missingTranscriptionAudio:
            "Could not find extracted audio."
        case .processFailed(let tool, let code, let detail):
            Self.describeFailure(tool: tool, code: code, detail: detail)
        case .emptyTranscript:
            "No speech was recognized in the audio."
        case .outputMissing(let name):
            "The tool finished but did not write \(name). Nothing was overwritten."
        }
    }

    static func describeFailure(tool: String, code: Int32, detail: String) -> String {
        var message = "\(tool) stopped with exit code \(code)."
        if !detail.isEmpty { message += "\n" + detail }
        if tool == "yt-dlp", ToolFailure.looksLikeOutdatedYtDlp(detail) {
            message += "\nThis often means yt-dlp is out of date. Open Tools & transcription to update it."
        }
        return message
    }
}
