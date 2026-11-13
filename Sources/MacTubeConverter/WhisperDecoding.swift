import Foundation

enum WhisperDecoding {
    /// Keep five-beam search; make repeated higher-temperature fallback passes opt-in.
    static func arguments(extraRetries: Bool) -> [String] {
        ["-bs", "5", "-bo", "5", "-tp", "0"] + (extraRetries ? [] : ["-nf"])
    }
}
