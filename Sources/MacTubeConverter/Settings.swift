import Foundation

enum Settings {
    static let legacyDomain = "com.local.MacTubeConverter"
    static let keys = ["outputFolder", "whisperModel", "downloadFormat", "conversionFormat", "conversionQuality",
                       "exportSubtitles", "singleVideoOnly", "transcriptionLanguage", "extraTranscriptionRetries",
                       "transcriptionVocabulary"]

    /// The bundle id changed in 1.2; carry over preferences saved by older builds once.
    static func migrateLegacyDefaults(into defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: "migratedLegacyDefaults") else { return }
        defaults.set(true, forKey: "migratedLegacyDefaults")
        guard Bundle.main.bundleIdentifier != legacyDomain,
              let legacy = UserDefaults(suiteName: legacyDomain) else { return }
        for key in keys where defaults.object(forKey: key) == nil {
            if let value = legacy.object(forKey: key) { defaults.set(value, forKey: key) }
        }
    }

    static func value<T: RawRepresentable>(_ key: String, default fallback: T) -> T where T.RawValue == String {
        UserDefaults.standard.string(forKey: key).flatMap(T.init(rawValue:)) ?? fallback
    }

    static func bool(_ key: String, default fallback: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? fallback
    }
}
