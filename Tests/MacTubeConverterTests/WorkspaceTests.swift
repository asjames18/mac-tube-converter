import XCTest
@testable import MacTubeConverter

final class WorkspaceTests: XCTestCase {
    @MainActor
    func testBatchConversionKeepsRemainingFilesAfterFailure() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = folder.appendingPathComponent("one.wav")
        let second = folder.appendingPathComponent("two.wav")
        try Data().write(to: first)
        try Data().write(to: second)
        let tool = folder.appendingPathComponent("fake-ffmpeg")
        try "#!/bin/sh\nexit 1\n".write(to: tool, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        let model = AppModel()
        model.selectedTab = .convert
        model.toolStatuses = [ToolStatus(name: "ffmpeg", path: tool.path, isRequired: true)]
        model.addFiles([first, second, first])
        XCTAssertEqual(model.queuedFiles.count, 2)
        await model.convertBatch()
        XCTAssertEqual(model.queuedFiles, [first, second])
        XCTAssertEqual(model.recentResults.count, 1)
        XCTAssertNil(model.recentResults.first?.output)
        XCTAssertFalse(model.isBusy)
        XCTAssertEqual(model.statusMessage, "Failed")
    }

    @MainActor
    func testBatchCancellationDoesNotStartNextFile() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let files = [folder.appendingPathComponent("one.wav"), folder.appendingPathComponent("two.wav")]
        for file in files { try Data().write(to: file) }
        let tool = folder.appendingPathComponent("fake-ffmpeg")
        try "#!/bin/sh\nexec /bin/sleep 30\n".write(to: tool, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        let model = AppModel()
        model.toolStatuses = [ToolStatus(name: "ffmpeg", path: tool.path, isRequired: true)]
        model.addFiles(files)
        let job = Task { await model.convertBatch() }
        try await Task.sleep(for: .milliseconds(200))
        model.cancelCurrentTask()
        await job.value
        XCTAssertEqual(model.recentResults.count, 1)
        XCTAssertEqual(model.queuedFiles, files)
        XCTAssertEqual(model.statusMessage, "Cancelled")
        XCTAssertFalse(model.isBusy)
    }

    @MainActor
    func testInvalidDownloadBatchCannotStart() {
        let model = AppModel()
        model.toolStatuses = ["ffmpeg", "yt-dlp"].map { ToolStatus(name: $0, path: "/usr/bin/true", isRequired: true) }
        model.videoURL = "https://example.com/video\nnot-a-link"
        XCTAssertEqual(model.downloadLinks.count, 2)
        XCTAssertEqual(model.readinessMessage, "Each link must be a complete http:// or https:// URL.")
    }

    @MainActor
    func testDownloadBatchRunsEachLinkAndRestoresInput() async {
        let model = AppModel()
        model.toolStatuses = ["ffmpeg", "yt-dlp"].map { ToolStatus(name: $0, path: "/usr/bin/true", isRequired: true) }
        let links = "https://example.com/one\nhttps://example.com/two"
        model.videoURL = links
        await model.startWorkspaceJob()
        XCTAssertEqual(model.recentResults.count, 2)
        XCTAssertEqual(model.recentResults.map(\.name), ["https://example.com/two", "https://example.com/one"])
        XCTAssertEqual(model.videoURL, links)
        XCTAssertEqual(model.statusMessage, "Finished 2 downloads")
        XCTAssertFalse(model.isBusy)
    }

    func testQualityPresetsChangeEncoderArguments() {
        let file = URL(fileURLWithPath: "/tmp/input.wav")
        let output = URL(fileURLWithPath: "/tmp/output.mp4")
        XCTAssertTrue(ConversionFormat.mp4.arguments(input: file, output: output, quality: .high).contains("18"))
        XCTAssertTrue(ConversionFormat.mp3.arguments(input: file, output: output, quality: .compact).contains("128k"))
    }
}
