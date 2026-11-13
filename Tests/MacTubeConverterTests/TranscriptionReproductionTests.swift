import XCTest
@testable import MacTubeConverter

final class TranscriptionReproductionTests: XCTestCase {
    @MainActor
    func testFullRecordingMakesProgressAndSavesOutput() async throws {
        guard let inputPath = ProcessInfo.processInfo.environment["MACTUBE_REPRO_AUDIO"],
              let modelPath = ProcessInfo.processInfo.environment["MACTUBE_REPRO_MODEL"],
              let outputPath = ProcessInfo.processInfo.environment["MACTUBE_REPRO_OUTPUT"] else {
            throw XCTSkip("Provide reproduction audio, model and output folder to run the full recording.")
        }
        let defaults = UserDefaults.standard
        let oldFolder = defaults.string(forKey: "outputFolder")
        let oldModel = defaults.string(forKey: "whisperModel")
        defer {
            defaults.set(oldFolder, forKey: "outputFolder")
            defaults.set(oldModel, forKey: "whisperModel")
        }
        let folder = URL(fileURLWithPath: outputPath)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let model = AppModel()
        model.modelPath = modelPath
        model.inputFile = URL(fileURLWithPath: inputPath)
        model.outputFolder = folder
        model.transcriptionSource = .file
        await model.refreshToolStatus()
        let job = Task { await model.startTranscription() }
        var sawLiveText = false
        var sawProgressBeyondSeven = false
        var progressLog = ""
        repeat {
            try await Task.sleep(for: .seconds(1))
            if model.isRunning {
                sawLiveText = sawLiveText || !model.transcriptText.isEmpty
                let progress = model.transcriptionProgress ?? 0
                sawProgressBeyondSeven = sawProgressBeyondSeven || (progress > 0.07 && progress < 1)
                progressLog += "\(Date()): \(Int(progress * 100))%, decoded audio \(model.decodedAudioSeconds)s, preview \(model.transcriptText.count) characters\n"
                try progressLog.write(to: folder.appendingPathComponent("progress.log"), atomically: true, encoding: .utf8)
            }
        } while model.isRunning
        await job.value
        try model.logText.write(to: folder.appendingPathComponent("whisper.log"), atomically: true, encoding: .utf8)
        XCTAssertEqual(model.statusMessage, "Transcript saved", model.logText)
        XCTAssertTrue(sawLiveText)
        XCTAssertTrue(sawProgressBeyondSeven)
        XCTAssertEqual(model.transcriptionProgress, 1)
        XCTAssertGreaterThan(model.decodedAudioSeconds, 330)
        XCTAssertNotNil(model.lastOutputURL)
    }
}
