import AppKit

extension AppModel {
    var downloadLinks: [String] {
        videoURL.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    var readinessMessage: String? {
        let required = selectedTab == .convert ? ["ffmpeg"] :
            selectedTab == .download ? ["yt-dlp", "ffmpeg"] :
            transcriptionSource == .url ? ["yt-dlp", "ffmpeg", "whisper-cli"] : ["ffmpeg", "whisper-cli"]
        let missing = required.filter { name in !toolStatuses.contains { $0.name == name && $0.isAvailable } }
        if !missing.isEmpty { return "Set up \(missing.joined(separator: ", ")) in Tools to continue." }
        if outputFolder == nil { return "Choose a destination folder." }
        if !outputFolderExists { return "The destination folder is no longer available. Choose another folder." }
        if selectedTab == .convert {
            if queuedFiles.isEmpty { return "Add audio or video files to get started." }
            if queuedFiles.contains(where: { !FileManager.default.isReadableFile(atPath: $0.path) }) { return "A source file is no longer available. Remove it and add it again." }
        } else if selectedTab == .download || transcriptionSource == .url {
            if downloadLinks.isEmpty { return "Paste a video link to get started." }
            if !downloadLinks.allSatisfy(OutputFiles.validWebURL) { return "Each link must be a complete http:// or https:// URL." }
            if selectedTab == .transcribe && downloadLinks.count != 1 { return "Use one video link at a time for transcription." }
        } else if inputFile == nil { return "Choose a file to transcribe." }
        if selectedTab == .transcribe && selectedModelIsMissing { return "The selected Whisper model file is missing. Choose another model in Tools." }
        if selectedTab == .transcribe && whisperModelURL() == nil { return "Add a Whisper model (ggml-*.bin) to ~/Library/Application Support/MacTubeConverter/Models or choose one in Tools." }
        if selectedTab == .transcribe && !canTranscribe { return "Choose a readable source and a compatible Whisper model in Tools." }
        return nil
    }

    func addFiles(_ urls: [URL]) {
        guard !isBusy else { return }
        var rejected = 0
        for url in urls {
            guard url.isFileURL, MediaTypes.isMedia(url),
                  FileManager.default.isReadableFile(atPath: url.path) else { rejected += 1; continue }
            if !queuedFiles.contains(url) { queuedFiles.append(url) }
        }
        inputMessage = rejected > 0 ? "\(rejected) item(s) could not be added. Choose readable audio or video files." : nil
    }

    func chooseConversionFiles() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = MediaTypes.panelTypes
        panel.prompt = "Add Files"
        if panel.runModal() == .OK { addFiles(panel.urls) }
    }

    /// Paste adds links to an existing Download list instead of replacing it.
    func pasteLinks(_ text: String) {
        let pasted = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pasted.isEmpty else { return }
        let current = videoURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if selectedTab == .download && !current.isEmpty {
            let existing = Set(downloadLinks)
            let additions = pasted.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !existing.contains($0) }
            guard !additions.isEmpty else { return }
            videoURL = ([current] + additions).joined(separator: "\n")
        } else {
            videoURL = pasted
        }
    }

    func startWorkspaceJob() async {
        guard !isBusy, readinessMessage == nil else { return }
        switch selectedTab {
        case .download: await downloadBatch()
        case .convert: await convertBatch()
        case .transcribe: await startTranscription()
        }
    }

    func convertBatch() async {
        guard !isBusy, !queuedFiles.isEmpty else { return }
        let files = queuedFiles
        let previousInput = inputFile
        batchRunning = true
        cancellationRequested = false
        batchCount = files.count
        resetLog()
        defer { batchRunning = false; inputFile = previousInput; flushLog() }
        for (index, file) in files.enumerated() {
            guard !cancellationRequested else { statusMessage = "Cancelled"; return }
            batchPosition = index + 1
            inputFile = file
            lastOutputURL = nil
            await startConversion()
            guard lastOutputURL != nil, statusMessage == "Completed" else { return }
            queuedFiles.removeAll { $0 == file }
        }
        statusMessage = "Converted \(files.count) file\(files.count == 1 ? "" : "s")"
    }

    func downloadBatch() async {
        guard !isBusy, !downloadLinks.isEmpty, downloadLinks.allSatisfy(OutputFiles.validWebURL) else { return }
        let links = downloadLinks
        let original = videoURL
        batchRunning = true
        cancellationRequested = false
        batchCount = links.count
        resetLog()
        defer { batchRunning = false; videoURL = original; flushLog() }
        for (index, link) in links.enumerated() {
            guard !cancellationRequested else { statusMessage = "Cancelled"; return }
            batchPosition = index + 1
            videoURL = link
            lastOutputURL = nil
            await startDownload()
            guard lastOutputURL != nil, statusMessage == "Completed" else { return }
        }
        statusMessage = "Finished \(links.count) download\(links.count == 1 ? "" : "s")"
    }
}
