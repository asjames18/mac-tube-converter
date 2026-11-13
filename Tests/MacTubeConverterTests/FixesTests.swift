import XCTest
@testable import MacTubeConverter

final class FixesTests: XCTestCase {
    private var savedFolder: String?
    private var savedModel: String?

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults.standard
        // Never let a test-created folder leak into other tests through saved preferences.
        if let path = defaults.string(forKey: "outputFolder"), !FileManager.default.fileExists(atPath: path) {
            defaults.removeObject(forKey: "outputFolder")
        }
        savedFolder = defaults.string(forKey: "outputFolder")
        savedModel = defaults.string(forKey: "whisperModel")
    }

    override func tearDown() {
        UserDefaults.standard.set(savedFolder, forKey: "outputFolder")
        UserDefaults.standard.set(savedModel, forKey: "whisperModel")
        super.tearDown()
    }

    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func script(_ body: String, in folder: URL, name: String = "fake-tool") throws -> URL {
        let tool = folder.appendingPathComponent(name)
        try "#!/bin/sh\n\(body)\n".write(to: tool, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        return tool
    }

    @MainActor
    func testCancelKillsGrandchildProcesses() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let pidFile = folder.appendingPathComponent("child.pid")
        // Like yt-dlp starting ffmpeg: the tool spawns a child that keeps the output pipe open.
        let tool = try script("/bin/sleep 60 &\necho $! > '\(pidFile.path)'\nwait", in: folder)
        let input = folder.appendingPathComponent("in.wav")
        try Data().write(to: input)
        let model = AppModel()
        model.inputFile = input
        model.outputFolder = folder
        model.toolStatuses = [ToolStatus(name: "ffmpeg", path: tool.path, isRequired: true)]
        let job = Task { await model.startConversion() }
        for _ in 0..<50 where !FileManager.default.fileExists(atPath: pidFile.path) {
            try await Task.sleep(for: .milliseconds(100))
        }
        model.flushLog()
        XCTAssertTrue(model.isRunning, model.logText + " / " + model.statusMessage)
        let childPID = try XCTUnwrap(pid_t(String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        let started = Date()
        model.cancelCurrentTask()
        await job.value
        XCTAssertLessThan(Date().timeIntervalSince(started), 10, "cancel must not wait for the grandchild to finish")
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertNotEqual(kill(childPID, 0), 0, "grandchild should be gone")
        XCTAssertEqual(model.statusMessage, "Cancelled")
    }

    @MainActor
    func testFailureShowsToolErrorAndRemovesPartialOutput() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent("clip.wav")
        try Data().write(to: input)
        // Write the output path (last argument), then fail with an error line.
        let tool = try script("for last; do :; done\necho partial > \"$last\"\necho 'Error: Invalid data found when processing input' >&2\nexit 1", in: folder, name: "ffmpeg")
        let model = AppModel()
        model.inputFile = input
        model.outputFolder = folder
        model.conversionFormat = .mp3
        model.toolStatuses = [ToolStatus(name: "ffmpeg", path: tool.path, isRequired: true)]
        await model.startConversion()
        model.flushLog()
        XCTAssertEqual(model.statusMessage, "Failed")
        XCTAssertTrue(model.logText.contains("Invalid data found"), model.logText)
        XCTAssertTrue(model.logText.contains("exit code 1"), model.logText)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("clip.mp3").path))
    }

    @MainActor
    func testConversionThatWritesNothingIsReportedAsFailed() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent("clip.wav")
        try Data().write(to: input)
        // Like ffmpeg 9 with -n and an existing output: prints an error but exits 0.
        let tool = try script("echo 'File already exists. Exiting.' >&2\nexit 0", in: folder, name: "ffmpeg")
        let model = AppModel()
        model.inputFile = input
        model.outputFolder = folder
        model.conversionFormat = .mp3
        model.toolStatuses = [ToolStatus(name: "ffmpeg", path: tool.path, isRequired: true)]
        await model.startConversion()
        XCTAssertEqual(model.statusMessage, "Failed")
        XCTAssertNil(model.lastOutputURL)
    }

    func testOutdatedYtDlpHint() {
        let message = AppError.describeFailure(tool: "yt-dlp", code: 1, detail: "ERROR: [youtube] abc: Sign in to confirm you're not a bot")
        XCTAssertTrue(message.contains("out of date"))
        XCTAssertFalse(AppError.describeFailure(tool: "ffmpeg", code: 1, detail: "Sign in").contains("out of date"))
    }

    func testOutputTailPrefersErrorsAndSkipsProgress() {
        var tail = ToolOutputTail()
        for line in ["[youtube] Extracting", "[download]  42.0% of 10MiB", "out_time_us=100", "ERROR: Unable to extract", "cleanup"] { tail.append(line) }
        XCTAssertEqual(tail.summary, "ERROR: Unable to extract")
    }

    func testMkvAndWebmAreAccepted() {
        XCTAssertTrue(MediaTypes.isMedia(URL(fileURLWithPath: "/tmp/a.mkv")))
        XCTAssertTrue(MediaTypes.isMedia(URL(fileURLWithPath: "/tmp/a.WEBM")))
        XCTAssertTrue(MediaTypes.isMedia(URL(fileURLWithPath: "/tmp/a.opus")))
        XCTAssertFalse(MediaTypes.isMedia(URL(fileURLWithPath: "/tmp/a.txt")))
    }

    @MainActor
    func testAddFilesAcceptsMkv() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("movie.mkv")
        try Data().write(to: file)
        let model = AppModel()
        model.addFiles([file])
        XCTAssertEqual(model.queuedFiles, [file])
    }

    func testPartialDownloadLeftoversOnlyMatchTempNames() {
        XCTAssertTrue(PartialFiles.isDownloadLeftover("Talk [abc].mp4.part"))
        XCTAssertTrue(PartialFiles.isDownloadLeftover("Talk [abc].f137.mp4"))
        XCTAssertTrue(PartialFiles.isDownloadLeftover("Talk [abc].mp4.part-Frag3"))
        XCTAssertFalse(PartialFiles.isDownloadLeftover("Talk [abc].mp4"))
    }

    func testPartialCleanupLeavesExistingFiles() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let old = folder.appendingPathComponent("old.mp4.part")
        try Data().write(to: old)
        let before = PartialFiles.snapshot(folder)
        try Data().write(to: folder.appendingPathComponent("new [x].webm.part"))
        try Data().write(to: folder.appendingPathComponent("keep.mp4"))
        XCTAssertEqual(PartialFiles.cleanDownloadLeftovers(in: folder, existingBefore: before), ["new [x].webm.part"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: old.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("keep.mp4").path))
    }

    func testVideoTitleAndSafeNames() {
        XCTAssertEqual(OutputFiles.videoTitle(fromDownloadedName: "My Talk: Part 1 [dQw4w9WgXcQ]"), "My Talk: Part 1")
        XCTAssertEqual(OutputFiles.safeFileName("My Talk: Part 1/2"), "My Talk- Part 1-2")
    }

    @MainActor
    func testMissingSelectedModelBlocksTranscription() {
        let oldPath = UserDefaults.standard.string(forKey: "whisperModel")
        defer { UserDefaults.standard.set(oldPath, forKey: "whisperModel") }
        let model = AppModel()
        model.modelPath = "/tmp/does-not-exist-\(UUID().uuidString)/ggml-small.en-q5_1.bin"
        model.selectedTab = .transcribe
        model.toolStatuses = ["ffmpeg", "yt-dlp", "whisper-cli"].map { ToolStatus(name: $0, path: "/usr/bin/true", isRequired: true) }
        model.videoURL = "https://example.com/v"
        XCTAssertNil(model.whisperModelURL())
        XCTAssertEqual(model.readinessMessage, "The selected Whisper model file is missing. Choose another model in Tools.")
    }

    @MainActor
    func testMissingOutputFolderIsReported() {
        let model = AppModel()
        let oldFolder = UserDefaults.standard.string(forKey: "outputFolder")
        defer { UserDefaults.standard.set(oldFolder, forKey: "outputFolder") }
        model.selectedTab = .download
        model.toolStatuses = ["ffmpeg", "yt-dlp"].map { ToolStatus(name: $0, path: "/usr/bin/true", isRequired: true) }
        model.videoURL = "https://example.com/v"
        model.outputFolder = URL(fileURLWithPath: "/tmp/missing-\(UUID().uuidString)")
        XCTAssertEqual(model.readinessMessage, "The destination folder is no longer available. Choose another folder.")
    }

    @MainActor
    func testPasteAppendsLinksInDownload() {
        let model = AppModel()
        model.selectedTab = .download
        model.videoURL = "https://example.com/one"
        model.pasteLinks("https://example.com/two\nhttps://example.com/one")
        XCTAssertEqual(model.downloadLinks, ["https://example.com/one", "https://example.com/two"])
        model.selectedTab = .transcribe
        model.pasteLinks("https://example.com/three")
        XCTAssertEqual(model.videoURL, "https://example.com/three")
    }

    func testProgressParsing() {
        XCTAssertEqual(MediaProgress.ytDlpPercent(in: "[download]  42.5% of   10.00MiB at  1.00MiB/s ETA 00:05"), 0.425)
        XCTAssertNil(MediaProgress.ytDlpPercent(in: "[youtube] 42%"))
        XCTAssertEqual(MediaProgress.ffmpegDuration(in: "  Duration: 00:01:02.50, start: 0.000000, bitrate: 1411 kb/s"), 62.5)
        XCTAssertEqual(MediaProgress.ffmpegOutTime(in: "out_time_us=12500000"), 12.5)
    }

    func testModelFolderOrder() {
        let home = URL(fileURLWithPath: "/Users/test")
        let folders = WhisperModelCatalog.searchFolders(environment: ["MACTUBE_MODEL_DIR": "/Volumes/Models"], home: home).map(\.path)
        XCTAssertEqual(Array(folders.prefix(3)), ["/Volumes/Models", "/Users/test/Library/Application Support/MacTubeConverter/Models", "/Users/test/Documents/Mac Apps/Models"])
    }

    func testBrewInfoParsing() {
        let json = #"{"formulae":[{"name":"yt-dlp","aliases":[],"versions":{"stable":"2026.10.26"},"installed":[{"version":"2026.03.17"}]},{"name":"whisper-cpp","aliases":[],"versions":{"stable":"1.9.5"},"installed":[{"version":"1.9.5"}]}]}"#
        let versions = ToolVersions.parse(Data(json.utf8))
        XCTAssertEqual(versions["yt-dlp"], ToolVersion(installed: "2026.03.17", latest: "2026.10.26"))
        XCTAssertTrue(versions["yt-dlp"]!.isOutdated)
        XCTAssertEqual(versions["whisper-cli"]?.isOutdated, false)
    }
}
