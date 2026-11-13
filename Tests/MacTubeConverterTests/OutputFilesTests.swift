import XCTest
@testable import MacTubeConverter

final class OutputFilesTests: XCTestCase {
    func testRejectsNonWebInputs() {
        for value in ["", "video", "file:///tmp/video.mp4", "--help", "https://"] {
            XCTAssertFalse(OutputFiles.validWebURL(value), value)
        }
        XCTAssertTrue(OutputFiles.validWebURL(" https://www.youtube.com/watch?v=123 \n"))
    }

    func testConversionDoesNotOverwriteExistingMedia() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = folder.appendingPathComponent("clip.mp4")
        try Data("original".utf8).write(to: original)
        let output = OutputFiles.availableURL(in: folder, name: "clip", extension: "mp4")
        XCTAssertEqual(output.lastPathComponent, "clip (2).mp4")
        try Data().write(to: output)
        XCTAssertEqual(OutputFiles.availableURL(in: folder, name: "clip", extension: "mp4").lastPathComponent, "clip (3).mp4")
        XCTAssertEqual(try String(contentsOf: original, encoding: .utf8), "original")
        for format in ConversionFormat.allCases {
            let arguments = format.arguments(input: original, output: output)
            XCTAssertTrue(arguments.contains("-n"))
            XCTAssertFalse(arguments.contains("-y"))
        }
    }
}
