import XCTest
@testable import MacTubeConverter

final class JSRuntimeTests: XCTestCase {
    private let bundled = URL(fileURLWithPath: "/Applications/MacTubeConverter.app/Contents/Resources/bin", isDirectory: true)

    func testDenoPathIsPassedToYtDlp() {
        XCTAssertEqual(ToolLocator.jsRuntimeArguments(denoPath: "/A/bin/deno"), ["--js-runtimes", "deno:/A/bin/deno"])
    }

    func testNoDenoMeansNoExtraArguments() {
        XCTAssertEqual(ToolLocator.jsRuntimeArguments(denoPath: nil), [])
        XCTAssertEqual(ToolLocator.jsRuntimeArguments(denoPath: ""), [])
    }

    func testBundledDenoWinsOverHomebrew() {
        let path = ToolLocator.resolve(named: "deno", bundledDirectory: bundled, environment: [:]) { _ in true }
        XCTAssertEqual(path, bundled.appendingPathComponent("deno").path)
        XCTAssertTrue(ToolLocator.isBundled(path, bundledDirectory: bundled))
    }

    func testBundledOnlyModeIgnoresHomebrewDeno() {
        let env = [ToolLocator.bundledOnlyKey: "1"]
        let path = ToolLocator.resolve(named: "deno", bundledDirectory: bundled, environment: env) { $0 == "/usr/local/bin/deno" }
        XCTAssertNil(path)
    }
}
