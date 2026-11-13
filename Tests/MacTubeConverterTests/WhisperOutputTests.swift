import XCTest
@testable import MacTubeConverter

final class WhisperOutputTests: XCTestCase {
    @MainActor
    func testQuantizedEnglishModelKeepsEnglishLanguage() throws {
        let oldPath = UserDefaults.standard.string(forKey: "whisperModel")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: folder)
            UserDefaults.standard.set(oldPath, forKey: "whisperModel")
        }
        let file = folder.appendingPathComponent("ggml-small.en-q5_1.bin")
        try Data().write(to: file)
        let model = AppModel()
        model.transcriptionLanguage = TranscriptionLanguage.supported[1]
        model.modelPath = file.path
        XCTAssertTrue(model.isEnglishOnlyModel)
        XCTAssertEqual(model.transcriptionLanguage.id, "en")
    }

    func testSinglePassRetainsBeamSearchAndMakesRetriesOptIn() {
        XCTAssertEqual(WhisperDecoding.arguments(extraRetries: false), ["-bs", "5", "-bo", "5", "-tp", "0", "-nf"])
        XCTAssertEqual(WhisperDecoding.arguments(extraRetries: true), ["-bs", "5", "-bo", "5", "-tp", "0"])
    }

    func testProgressAndTimestampedSpeech() {
        XCTAssertEqual(WhisperOutput.progress(in: "whisper_print_progress_callback: progress =   7%"), 0.07)
        XCTAssertNil(WhisperOutput.progress(in: "download 7%"))
        XCTAssertEqual(WhisperOutput.segment(in: "[00:00:13.300 --> 00:00:14.200]   café ♪")?.text, "café ♪")
        XCTAssertEqual(WhisperOutput.segment(in: "[00:01:13.300 --> 00:01:14.200]   hello")?.endSeconds, 74.2)
    }

    func testSplitUTF8AndUnterminatedLastLineArePreserved() {
        var decoder = ProcessLineDecoder()
        let bytes = Array("first\r\ncafé ♪\nlast".utf8)
        var lines: [String] = []
        for byte in bytes { lines += decoder.append(Data([byte])) }
        lines += decoder.finish()
        XCTAssertEqual(lines, ["first", "café ♪", "last"])
    }
}
