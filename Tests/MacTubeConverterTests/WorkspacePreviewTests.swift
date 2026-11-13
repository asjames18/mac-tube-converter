import AppKit
import SwiftUI
import XCTest
@testable import MacTubeConverter

final class WorkspacePreviewTests: XCTestCase {
    @MainActor
    func testRenderWorkspace() throws {
        guard let directory = ProcessInfo.processInfo.environment["MACTUBE_PREVIEW_DIR"] else {
            throw XCTSkip("Set MACTUBE_PREVIEW_DIR to render native workspace previews.")
        }
        _ = NSApplication.shared
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        for tab in AppTab.allCases {
            let model = AppModel()
            model.selectedTab = tab
            model.toolStatuses = ["ffmpeg", "yt-dlp", "whisper-cli"].map { ToolStatus(name: $0, path: "/usr/local/bin/\($0)", isRequired: true) }
            let view = NSHostingView(rootView: ContentView(model: model))
            view.frame = NSRect(x: 0, y: 0, width: 1200, height: 860)
            let window = NSWindow(contentRect: view.frame, styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.contentView = view
            view.layoutSubtreeIfNeeded()
            view.displayIfNeeded()
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return XCTFail("Could not render view") }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(tab.rawValue).png"))
            window.orderOut(nil)
        }
    }
}
