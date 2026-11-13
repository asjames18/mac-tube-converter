import XCTest
@testable import MacTubeConverter

final class WorkflowTests: XCTestCase {
    @MainActor
    func testLocalConversionAndSubtitleExport() async throws {
        guard ProcessInfo.processInfo.environment["MACTUBE_INTEGRATION_TESTS"] == "1" else {
            throw XCTSkip("Set MACTUBE_INTEGRATION_TESTS=1 to exercise local media tools.")
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let defaults = UserDefaults.standard
        let oldFolder = defaults.string(forKey: "outputFolder")
        let oldModel = defaults.string(forKey: "whisperModel")
        defer {
            try? FileManager.default.removeItem(at: folder)
            defaults.set(oldFolder, forKey: "outputFolder")
            defaults.set(oldModel, forKey: "whisperModel")
        }
        let input = folder.appendingPathComponent("sample.aiff")
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-o", input.path, "Welcome to Mac Tube Converter. This is a test of local transcription and subtitle export."]
        try say.run()
        say.waitUntilExit()
        XCTAssertEqual(say.terminationStatus, 0)
        let model = AppModel()
        await model.refreshToolStatus()
        model.modelPath = model.availableWhisperModels.first { $0.lastPathComponent == "ggml-base.en.bin" }?.path ?? ""
        model.inputFile = input
        model.outputFolder = folder
        model.conversionFormat = .wav
        await model.startConversion()
        XCTAssertEqual(model.statusMessage, "Completed", model.logText)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("sample.wav").path))
        model.transcriptionSource = .file
        model.exportSubtitles = true
        await model.startTranscription()
        XCTAssertEqual(model.statusMessage, "Transcript saved", model.logText)
        XCTAssertFalse(model.transcriptText.isEmpty)
        XCTAssertGreaterThan(model.transcriptionAudioDuration ?? 0, 1)
        XCTAssertEqual(model.transcriptionProgress, 1)
        let srt = try String(contentsOf: folder.appendingPathComponent("sample-transcript.srt"), encoding: .utf8)
        XCTAssertTrue(srt.contains("-->"))
        XCTAssertFalse(model.isRunning)
        model.selectedTab = .convert
        model.addFiles([input, folder.appendingPathComponent("sample.wav")])
        model.conversionFormat = .mp3
        model.conversionQuality = .compact
        await model.startWorkspaceJob()
        XCTAssertEqual(model.statusMessage, "Converted 2 files", model.logText)
        XCTAssertTrue(model.queuedFiles.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("sample.mp3").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("sample (2).mp3").path))
    }

    @MainActor
    func testCancellationStopsJob() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let tool = folder.appendingPathComponent("fake-ffmpeg")
        try "#!/bin/sh\nexec /bin/sleep 30\n".write(to: tool, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        let model = AppModel()
        model.inputFile = tool
        model.toolStatuses = [ToolStatus(name: "ffmpeg", path: tool.path, isRequired: true)]
        let job = Task { await model.startConversion() }
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(model.isRunning)
        model.cancelCurrentTask()
        await job.value
        XCTAssertFalse(model.isRunning)
        XCTAssertEqual(model.statusMessage, "Cancelled")
        XCTAssertNil(model.lastOutputURL)
    }
}
