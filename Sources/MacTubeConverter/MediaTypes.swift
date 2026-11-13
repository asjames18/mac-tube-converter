import UniformTypeIdentifiers

/// macOS does not classify every common container (for example .mkv) as a movie,
/// so media is also accepted by file extension.
enum MediaTypes {
    static let videoExtensions: Set<String> = ["mp4", "m4v", "mov", "mkv", "webm", "avi", "flv", "wmv", "mpg", "mpeg", "ts", "m2ts", "mts", "3gp", "ogv"]
    static let audioExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "aif", "aiff", "flac", "opus", "ogg", "oga", "wma", "caf", "alac"]

    static func isMedia(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if videoExtensions.contains(ext) || audioExtensions.contains(ext) { return true }
        guard let type = UTType(filenameExtension: ext) else { return false }
        return type.conforms(to: .audio) || type.conforms(to: .movie)
    }

    static var panelTypes: [UTType] {
        [.audio, .movie, .mpeg4Movie, .quickTimeMovie]
            + (videoExtensions.union(audioExtensions)).sorted().compactMap { UTType(filenameExtension: $0) }
    }
}
