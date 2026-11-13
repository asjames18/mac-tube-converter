import XCTest
@testable import MacTubeConverter

final class BundledToolsTests: XCTestCase {
    private let bundled = URL(fileURLWithPath: "/Applications/MacTubeConverter.app/Contents/Resources/bin", isDirectory: true)

    func testBundledCopyWinsOverHomebrew() {
        let path = ToolLocator.resolve(named: "ffmpeg", bundledDirectory: bundled, environment: [:]) { _ in true }
        XCTAssertEqual(path, bundled.appendingPathComponent("ffmpeg").path)
        XCTAssertTrue(ToolLocator.isBundled(path, bundledDirectory: bundled))
    }

    func testFallsBackToHomebrewWhenNotBundled() {
        let path = ToolLocator.resolve(named: "yt-dlp", bundledDirectory: bundled, environment: [:]) { $0 == "/usr/local/bin/yt-dlp" }
        XCTAssertEqual(path, "/usr/local/bin/yt-dlp")
        XCTAssertFalse(ToolLocator.isBundled(path, bundledDirectory: bundled))
    }

    func testBundledOnlyModeIgnoresSystemCopies() {
        let env = [ToolLocator.bundledOnlyKey: "1"]
        XCTAssertEqual(ToolLocator.candidates(named: "whisper-cli", bundledDirectory: bundled, environment: env),
                       [bundled.appendingPathComponent("whisper-cli").path])
        XCTAssertNil(ToolLocator.resolve(named: "whisper-cli", bundledDirectory: bundled, environment: env) { !$0.hasPrefix(self.bundled.path) })
    }

    func testCandidateOrder() {
        XCTAssertEqual(ToolLocator.candidates(named: "ffmpeg", bundledDirectory: bundled, environment: [:]),
                       [bundled.appendingPathComponent("ffmpeg").path, "/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"])
        XCTAssertEqual(ToolLocator.candidates(named: "ffmpeg", bundledDirectory: nil, environment: [:]).first, "/opt/homebrew/bin/ffmpeg")
    }

    func testChildProcessPathPutsBundledFolderFirst() {
        XCTAssertEqual(ToolLocator.searchPath(existing: "/custom", bundledDirectory: bundled, environment: [:]),
                       "\(bundled.path):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/custom")
        XCTAssertEqual(ToolLocator.searchPath(existing: "/usr/local/bin", bundledDirectory: bundled, environment: [ToolLocator.bundledOnlyKey: "1"]),
                       "\(bundled.path):/usr/bin:/bin")
    }

    func testRecommendedModelIsTheAppsPreferredModel() {
        XCTAssertEqual(WhisperModelCatalog.preferredNames.first, DownloadableModel.recommended.fileName)
        XCTAssertTrue(ModelInstaller.destinationFolder(home: URL(fileURLWithPath: "/Users/x")).path
            .hasSuffix("Library/Application Support/MacTubeConverter/Models"))
        XCTAssertTrue(WhisperModelCatalog.searchFolders(environment: [:], home: URL(fileURLWithPath: "/Users/x"))
            .contains(ModelInstaller.destinationFolder(home: URL(fileURLWithPath: "/Users/x"))))
    }

    func testInstallerVerifiesAndMovesModel() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let data = Data("hello model".utf8)
        let staged = dir.appendingPathComponent("staged.part")
        try data.write(to: staged)
        let sha = try ModelInstaller.sha256(of: staged)
        let model = DownloadableModel(fileName: "ggml-test.bin", url: URL(string: "https://example.invalid/m")!, sha256: sha, bytes: Int64(data.count))
        let installed = try ModelInstaller.install(staged: staged, model: model, into: dir.appendingPathComponent("Models"))
        XCTAssertEqual(installed.lastPathComponent, "ggml-test.bin")
        XCTAssertEqual(try Data(contentsOf: installed), data)
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.path))
    }

    func testInstallerRejectsBadChecksumAndDeletesFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let staged = dir.appendingPathComponent("staged.part")
        try Data("tampered".utf8).write(to: staged)
        let model = DownloadableModel(fileName: "ggml-test.bin", url: URL(string: "https://example.invalid/m")!, sha256: String(repeating: "0", count: 64), bytes: 8)
        XCTAssertThrowsError(try ModelInstaller.install(staged: staged, model: model, into: dir)) {
            XCTAssertEqual($0 as? ModelInstallError, .checksumMismatch)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.path))
        let short = DownloadableModel(fileName: "x.bin", url: model.url, sha256: model.sha256, bytes: 99)
        try Data("tampered".utf8).write(to: staged)
        XCTAssertThrowsError(try ModelInstaller.install(staged: staged, model: short, into: dir)) {
            XCTAssertEqual($0 as? ModelInstallError, .sizeMismatch(expected: 99, actual: 8))
        }
    }

    func testKnownSHA256() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("abc".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertEqual(try ModelInstaller.sha256(of: file), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}
