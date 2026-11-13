import AppKit
import AVFoundation
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var selectedTab: AppTab = .download
    @Published var videoURL = ""
    @Published var downloadFormat: DownloadFormat = Settings.value("downloadFormat", default: .mp4) {
        didSet { UserDefaults.standard.set(downloadFormat.rawValue, forKey: "downloadFormat") }
    }
    @Published var singleVideoOnly = Settings.bool("singleVideoOnly", default: true) {
        didSet { UserDefaults.standard.set(singleVideoOnly, forKey: "singleVideoOnly") }
    }
    @Published var inputFile: URL?
    @Published var outputFolder: URL? = UserDefaults.standard.string(forKey: "outputFolder").map { URL(fileURLWithPath: $0) }
        ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
        didSet { UserDefaults.standard.set(outputFolder?.path, forKey: "outputFolder") }
    }
    @Published var exportSubtitles = Settings.bool("exportSubtitles", default: true) {
        didSet { UserDefaults.standard.set(exportSubtitles, forKey: "exportSubtitles") }
    }
    @Published var statusMessage = "Ready"
    @Published var lastOutputURL: URL?
    @Published var modelPath = UserDefaults.standard.string(forKey: "whisperModel") ?? "" {
        didSet {
            UserDefaults.standard.set(modelPath, forKey: "whisperModel")
            if isEnglishOnlyModel { transcriptionLanguage = TranscriptionLanguage.supported[0] }
        }
    }
    @Published var queuedFiles: [URL] = []
    @Published var conversionQuality: ConversionQuality = Settings.value("conversionQuality", default: .balanced) {
        didSet { UserDefaults.standard.set(conversionQuality.rawValue, forKey: "conversionQuality") }
    }
    @Published var batchRunning = false
    @Published var batchPosition = 0
    @Published var batchCount = 0
    @Published var recentResults: [JobResult] = []
    @Published var inputMessage: String?
    var isBusy: Bool { isRunning || batchRunning }
    /// Set by Cancel; reset only when a new job or batch starts, so a cancel between batch items is kept.
    var cancellationRequested = false
    @Published var conversionFormat: ConversionFormat = Settings.value("conversionFormat", default: .mp4) {
        didSet { UserDefaults.standard.set(conversionFormat.rawValue, forKey: "conversionFormat") }
    }
    @Published var transcriptionSource: TranscriptionSource = .url
    @Published var transcriptionLanguage = TranscriptionLanguage.saved() {
        didSet { UserDefaults.standard.set(transcriptionLanguage.id, forKey: "transcriptionLanguage") }
    }
    @Published var transcriptText = ""
    @Published var transcriptionProgress: Double?
    @Published var transcriptionStartedAt: Date?
    @Published var lastTranscriptUpdate: Date?
    @Published var decodedAudioSeconds: Double = 0
    @Published var transcriptionAudioDuration: Double?
    @Published var transcriptionVocabulary = UserDefaults.standard.string(forKey: "transcriptionVocabulary") ?? "" {
        didSet { UserDefaults.standard.set(transcriptionVocabulary, forKey: "transcriptionVocabulary") }
    }
    @Published var extraTranscriptionRetries = Settings.bool("extraTranscriptionRetries", default: false) {
        didSet { UserDefaults.standard.set(extraTranscriptionRetries, forKey: "extraTranscriptionRetries") }
    }
    @Published var availableWhisperModels: [URL] = []
    /// Title of the video being transcribed from a link, used for file names and results.
    @Published var transcriptionSourceName: String?
    /// 0...1 for downloads and conversions when the tool reports it; nil shows an indeterminate spinner.
    @Published var jobProgress: Double?
    @Published var toolVersions: [String: ToolVersion] = [:]
    @Published var suggestYtDlpUpdate = false
    /// Shown once per launch when no Whisper model is installed.
    @Published var showModelSetup = false
    private var modelSetupOffered = false
    let modelDownloader = ModelDownloader()
    private var receivingTranscription = false
    @Published var logText = ""
    private var pendingLog: [String] = []
    private var logFlushScheduled = false
    @Published var isRunning = false
    @Published var toolStatuses: [ToolStatus] = [
        ToolStatus(name: "yt-dlp", path: nil, isRequired: true),
        ToolStatus(name: "ffmpeg", path: nil, isRequired: true),
        ToolStatus(name: "whisper-cli", path: nil, isRequired: true)
    ]

    private var currentProcess: Process?
    private var mediaDuration: Double?
    private var terminationObserver: NSObjectProtocol?

    init() {
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopProcessesForQuit() }
        }
    }

    var canDownload: Bool {
        OutputFiles.validWebURL(videoURL)
            && outputFolderExists
            && toolPath("yt-dlp") != nil
            && toolPath("ffmpeg") != nil
    }

    var canConvert: Bool {
        inputFile.map { FileManager.default.isReadableFile(atPath: $0.path) } == true && outputFolderExists && toolPath("ffmpeg") != nil
    }

    var canTranscribe: Bool {
        outputFolderExists
            && toolPath("ffmpeg") != nil
            && toolPath("whisper-cli") != nil
            && whisperModelURL() != nil
            && (!isEnglishOnlyModel || transcriptionLanguage.id == "en")
            && (transcriptionSource == .file ? inputFile.map { FileManager.default.isReadableFile(atPath: $0.path) } == true : canDownload)
    }

    var outputFolderExists: Bool {
        guard let outputFolder else { return false }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: outputFolder.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    /// True when a model was chosen explicitly but its file is gone.
    var selectedModelIsMissing: Bool {
        !modelPath.isEmpty && !FileManager.default.isReadableFile(atPath: modelPath)
    }

    func refreshToolStatus() async {
        var updated: [ToolStatus] = []

        for name in ["yt-dlp", "ffmpeg", "whisper-cli"] {
            let path = await ToolLocator.findExecutable(named: name)
            updated.append(ToolStatus(name: name, path: path, isRequired: true))
        }

        toolStatuses = updated
        appendLog("Tool check complete.")
        let folders = WhisperModelCatalog.searchFolders()
        availableWhisperModels = await Task.detached(priority: .utility) {
            WhisperModelCatalog.find(in: folders)
        }.value
        if !modelPath.isEmpty, !selectedModelIsMissing {
            let custom = URL(fileURLWithPath: modelPath)
            if !availableWhisperModels.contains(custom) { availableWhisperModels.append(custom) }
        }
        if selectedModelIsMissing { appendLog("Selected Whisper model is missing: \(modelPath)") }
        appendLog(whisperModelURL() == nil ? "Whisper model missing." : "Whisper model found.")
        if whisperModelURL() == nil, modelPath.isEmpty, !modelSetupOffered,
           ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            modelSetupOffered = true
            showModelSetup = true
        }
        flushLog()
    }

    func refreshToolVersions() async {
        toolVersions = await ToolVersions.fetch()
    }

    var canUpdateYtDlp: Bool { ToolVersions.brewPath() != nil && !isBusy && !ToolLocator.isBundled(toolPath("yt-dlp")) }

    /// Runs `brew upgrade yt-dlp`. The UI asks for confirmation before calling this.
    func updateYtDlp() async {
        guard let brew = ToolVersions.brewPath(), !isBusy else { return }
        isRunning = true
        cancellationRequested = false
        resetLog()
        jobProgress = nil
        do {
            try await runProcess(tool: brew, arguments: ["upgrade", "yt-dlp"], title: "Updating yt-dlp with Homebrew...",
                                 extraEnvironment: ["HOMEBREW_NO_ENV_HINTS": "1"])
            statusMessage = "yt-dlp updated"
            suggestYtDlpUpdate = false
        } catch {
            statusMessage = cancellationRequested ? "Cancelled" : "yt-dlp update failed"
            appendLog("Update failed: \(error.localizedDescription)")
        }
        currentProcess = nil
        isRunning = false
        flushLog()
        await refreshToolStatus()
        await refreshToolVersions()
    }

    func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"

        if panel.runModal() == .OK {
            outputFolder = panel.url
        }
    }

    func chooseInputFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = MediaTypes.panelTypes
        panel.prompt = "Choose"

        if panel.runModal() == .OK, let url = panel.url {
            setTranscriptionFile(url)
        }
    }

    /// Used by the Transcribe file picker and drop area.
    @discardableResult
    func setTranscriptionFile(_ url: URL) -> Bool {
        guard !isBusy, url.isFileURL, MediaTypes.isMedia(url), FileManager.default.isReadableFile(atPath: url.path) else {
            inputMessage = "Choose a readable audio or video file."
            return false
        }
        inputMessage = nil
        inputFile = url
        transcriptionSource = .file
        return true
    }

    func startDownload() async {
        guard canDownload, let ytDLP = toolPath("yt-dlp"), let ffmpeg = toolPath("ffmpeg"), let folder = outputFolder else { return }
        let trimmedURL = videoURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else { return }

        let pathFile = FileManager.default.temporaryDirectory.appendingPathComponent("MacTubeConverter-path-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: pathFile) }
        var arguments = downloadFormat.arguments + ToolLocator.jsRuntimeArguments() + ["--no-overwrites", "--newline", "--ffmpeg-location", ffmpeg,
                                                    "--print-to-file", "after_move:filepath", pathFile.path(percentEncoded: false)]
        if singleVideoOnly {
            arguments.append("--no-playlist")
        }
        arguments += [
            "-P", folder.path(percentEncoded: false),
            "-o", "%(title).200B [%(id)s].%(ext)s",
            "--", trimmedURL
        ]

        let before = PartialFiles.snapshot(folder)
        await run(tool: ytDLP, arguments: arguments, title: "Starting download...", output: folder, operation: .download) { [weak self] succeeded in
            guard let self else { return }
            if succeeded {
                // Open the downloaded file itself when yt-dlp reported it; otherwise fall back to the folder.
                let printed = (try? String(contentsOf: pathFile, encoding: .utf8))?
                    .components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } ?? []
                if let last = printed.last, FileManager.default.fileExists(atPath: last) {
                    self.lastOutputURL = URL(fileURLWithPath: last)
                }
            } else {
                let removed = PartialFiles.cleanDownloadLeftovers(in: folder, existingBefore: before)
                if !removed.isEmpty { self.appendLog("Moved \(removed.count) partial download file(s) to the Trash.") }
            }
        }
    }

    func startConversion() async {
        guard canConvert, let ffmpeg = toolPath("ffmpeg"), let inputFile, let folder = outputFolder else { return }
        let baseName = inputFile.deletingPathExtension().lastPathComponent
        let output = OutputFiles.availableURL(in: folder, name: baseName, extension: conversionFormat.fileExtension)
        await run(tool: ffmpeg, arguments: conversionFormat.arguments(input: inputFile, output: output, quality: conversionQuality), title: "Starting conversion...", output: output, operation: .convert) { [weak self] succeeded in
            if !succeeded, FileManager.default.fileExists(atPath: output.path) {
                PartialFiles.discard(output)
                self?.appendLog("Moved the incomplete \(output.lastPathComponent) to the Trash.")
            }
        }
    }

    func startTranscription() async {
        guard !isRunning, canTranscribe,
              let ffmpeg = toolPath("ffmpeg"),
              let whisper = toolPath("whisper-cli"),
              let modelURL = whisperModelURL(),
              let folder = outputFolder else { return }

        isRunning = true
        if !batchRunning { cancellationRequested = false }
        lastOutputURL = nil
        resetLog()
        transcriptText = ""
        transcriptionProgress = nil
        jobProgress = nil
        decodedAudioSeconds = 0
        transcriptionAudioDuration = nil
        transcriptionSourceName = transcriptionSource == .file ? inputFile?.deletingPathExtension().lastPathComponent : nil
        transcriptionStartedAt = Date()
        lastTranscriptUpdate = nil
        suggestYtDlpUpdate = false
        appendLog("Preparing transcription with Whisper...")

        let tempFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacTubeConverter-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempFolder) }
        do {
            guard FileManager.default.isReadableFile(atPath: modelURL.path) else { throw AppError.missingModel }
            try FileManager.default.createDirectory(at: tempFolder, withIntermediateDirectories: true)
            let audioURL = try await prepareTranscriptionAudio(ffmpeg: ffmpeg, tempFolder: tempFolder)
            let preparedAudio = try AVAudioFile(forReading: audioURL)
            transcriptionAudioDuration = Double(preparedAudio.length) / preparedAudio.fileFormat.sampleRate
            let transcript = try await transcribeWithWhisper(audioURL, whisper: whisper, modelURL: modelURL)
            transcriptText = transcript

            let outputURL = OutputFiles.availableURL(in: folder, name: transcriptBaseName(), extension: "txt")
            try transcript.write(to: outputURL, atomically: true, encoding: .utf8)
            lastOutputURL = outputURL
            transcriptionProgress = 1
            statusMessage = "Transcript saved"
            appendLog("Transcript saved: \(outputURL.path(percentEncoded: false))")

            if exportSubtitles {
                // The transcript is already safe; a subtitle problem must not be reported as a failed job.
                do {
                    let subtitle = tempFolder.appendingPathComponent("whisper-transcript.srt")
                    let destination = OutputFiles.availableURL(in: folder, name: outputURL.deletingPathExtension().lastPathComponent, extension: "srt")
                    try FileManager.default.copyItem(at: subtitle, to: destination)
                    appendLog("Subtitles saved: \(destination.path)")
                } catch {
                    statusMessage = "Transcript saved · subtitles failed"
                    appendLog("Subtitles could not be saved: \(error.localizedDescription)")
                }
            }
            appendLog("Done.")
        } catch {
            statusMessage = cancellationRequested ? "Cancelled" : "Transcription failed"
            appendLog("Transcription failed: \(error.localizedDescription)")
            noteFailure(error)
        }

        let name = transcriptionSourceName ?? (transcriptionSource == .file ? inputFile?.lastPathComponent : videoURL.trimmingCharacters(in: .whitespacesAndNewlines)) ?? "Transcript"
        recentResults.insert(JobResult(name: name, operation: "Transcribe", output: lastOutputURL, message: statusMessage), at: 0)
        recentResults = Array(recentResults.prefix(30))
        currentProcess = nil
        isRunning = false
        flushLog()
    }

    func cancelCurrentTask() {
        guard isBusy else { return }
        cancellationRequested = true
        statusMessage = "Cancelling…"
        if let process = currentProcess, process.isRunning {
            ProcessTree.terminateTree(root: process.processIdentifier)
        }
        appendLog("Cancel requested.")
    }

    /// Called when the app quits so no tool keeps running in the background.
    func stopProcessesForQuit() {
        cancellationRequested = true
        if let process = currentProcess, process.isRunning {
            ProcessTree.killTreeNow(root: process.processIdentifier)
        }
    }

    private func prepareTranscriptionAudio(ffmpeg: String, tempFolder: URL) async throws -> URL {
        switch transcriptionSource {
        case .file:
            guard let inputFile else { throw AppError.missingInput }
            let audioURL = tempFolder.appendingPathComponent("transcription.wav")
            try await runProcess(
                tool: ffmpeg,
                arguments: ["-nostdin", "-y", "-i", inputFile.path(percentEncoded: false), "-vn", "-ac", "1", "-ar", "16000", "-c:a", "pcm_s16le", audioURL.path(percentEncoded: false)],
                title: "Extracting audio with ffmpeg..."
            )
            return audioURL

        case .url:
            guard let ytDLP = toolPath("yt-dlp") else { throw AppError.missingTool("yt-dlp") }
            let trimmedURL = videoURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedURL.isEmpty else { throw AppError.missingInput }

            let template = tempFolder.appendingPathComponent("%(title).150B [%(id)s].%(ext)s").path(percentEncoded: false)
            try await runProcess(
                tool: ytDLP,
                arguments: ToolLocator.jsRuntimeArguments() + ["-f", "bestaudio/best", "--no-playlist", "--newline", "-x", "--audio-format", "wav", "--postprocessor-args", "ffmpeg:-ac 1 -ar 16000", "--ffmpeg-location", ffmpeg, "-o", template, "--", trimmedURL],
                title: "Downloading audio with yt-dlp..."
            )

            let files = try FileManager.default.contentsOfDirectory(at: tempFolder, includingPropertiesForKeys: nil)
            guard let wav = files.first(where: { $0.pathExtension.lowercased() == "wav" }) else {
                throw AppError.missingTranscriptionAudio
            }
            transcriptionSourceName = OutputFiles.videoTitle(fromDownloadedName: wav.deletingPathExtension().lastPathComponent)
            jobProgress = nil
            return wav
        }
    }

    private func transcribeWithWhisper(_ audioURL: URL, whisper: String, modelURL: URL) async throws -> String {
        appendLog("Model: \(modelURL.lastPathComponent). Decoding full audio; progress updates after each section.")
        receivingTranscription = true
        transcriptionProgress = 0
        lastTranscriptUpdate = Date()
        defer { receivingTranscription = false }

        let outputBase = audioURL.deletingLastPathComponent().appendingPathComponent("whisper-transcript")
        try await runProcess(
            tool: whisper,
            arguments: [
                "-m", modelURL.path(percentEncoded: false),
                "-f", audioURL.path(percentEncoded: false),
                "-l", transcriptionLanguage.id,
                "-otxt",
                "-of", outputBase.path(percentEncoded: false),
                "-pp"
            ] + WhisperDecoding.arguments(extraRetries: extraTranscriptionRetries)
                + (exportSubtitles ? ["-osrt"] : [])
                + (transcriptionVocabulary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : ["--prompt", transcriptionVocabulary]),
            title: "Transcribing with whisper-cli..."
        )

        let transcriptURL = outputBase.appendingPathExtension("txt")
        let transcript = try String(contentsOf: transcriptURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { throw AppError.emptyTranscript }
        return transcript
    }

    private func run(tool: String, arguments: [String], title: String, output: URL, operation: AppTab,
                     finish: ((Bool) -> Void)? = nil) async {
        guard !isRunning else { return }
        isRunning = true
        if !batchRunning { cancellationRequested = false; resetLog() }
        lastOutputURL = nil
        jobProgress = nil
        suggestYtDlpUpdate = false

        var succeeded = false
        do {
            try await runProcess(tool: tool, arguments: arguments, title: title)
            // ffmpeg 9 exits 0 when -n refuses to overwrite, so confirm a conversion really wrote its file.
            if operation == .convert {
                let size = (try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                guard size > 0 else { throw AppError.outputMissing(output.lastPathComponent) }
            }
            lastOutputURL = output
            statusMessage = "Completed"
            succeeded = true
        } catch {
            statusMessage = cancellationRequested ? "Cancelled" : "Failed"
            appendLog("Failed: \(error.localizedDescription)")
            noteFailure(error)
        }
        finish?(succeeded)
        if succeeded { appendLog("Done.") }

        let name = operation == .download ? videoURL : (inputFile?.lastPathComponent ?? output.lastPathComponent)
        recentResults.insert(JobResult(name: name, operation: operation.title, output: lastOutputURL, message: statusMessage), at: 0)
        recentResults = Array(recentResults.prefix(30))
        currentProcess = nil
        jobProgress = nil
        isRunning = false
        flushLog()
    }

    private func noteFailure(_ error: Error) {
        guard !cancellationRequested, case AppError.processFailed(let tool, _, let detail) = error else { return }
        if tool == "yt-dlp", ToolFailure.looksLikeOutdatedYtDlp(detail) { suggestYtDlpUpdate = true }
    }

    private func runProcess(tool: String, arguments: [String], title: String, extraEnvironment: [String: String] = [:]) async throws {
        guard !cancellationRequested else { throw CancellationError() }
        statusMessage = title
        appendLog(title)
        mediaDuration = nil

        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = ToolLocator.searchPath(existing: environment["PATH"])
        environment.merge(extraEnvironment) { _, new in new }
        process.environment = environment
        process.standardInput = FileHandle.nullDevice

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        currentProcess = process

        let stream = AsyncStream<Data> { continuation in
            outputPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty { continuation.finish() }
                else { continuation.yield(data) }
            }
        }
        defer { outputPipe.fileHandleForReading.readabilityHandler = nil }
        try process.run()
        try? outputPipe.fileHandleForWriting.close()
        // Cancel may have arrived while the process was starting.
        if cancellationRequested { ProcessTree.terminateTree(root: process.processIdentifier) }
        var decoder = ProcessLineDecoder()
        var tail = ToolOutputTail()
        for await data in stream {
            for line in decoder.append(data) { tail.append(line); receiveProcessLine(line) }
        }
        for line in decoder.finish() { tail.append(line); receiveProcessLine(line) }
        let terminationStatus = await Task.detached(priority: .utility) {
            process.waitUntilExit()
            return process.terminationStatus
        }.value

        currentProcess = nil
        guard !cancellationRequested else { throw CancellationError() }
        guard terminationStatus == 0 else {
            throw AppError.processFailed(URL(fileURLWithPath: tool).lastPathComponent, terminationStatus, tail.summary)
        }
    }

    private func receiveProcessLine(_ line: String) {
        if !ToolOutputTail.isProgressNoise(line) || line.contains("whisper_print_progress_callback") { appendLog(line) }
        if !receivingTranscription {
            if let percent = MediaProgress.ytDlpPercent(in: line) { jobProgress = percent }
            if mediaDuration == nil, let duration = MediaProgress.ffmpegDuration(in: line), duration > 0 { mediaDuration = duration }
            if let time = MediaProgress.ffmpegOutTime(in: line), let duration = mediaDuration { jobProgress = min(1, time / duration) }
            return
        }
        if let progress = WhisperOutput.progress(in: line) {
            transcriptionProgress = max(transcriptionProgress ?? 0, min(progress, 0.99))
            lastTranscriptUpdate = Date()
        }
        if let segment = WhisperOutput.segment(in: line) {
            transcriptText += (transcriptText.isEmpty ? "" : "\n") + segment.text
            decodedAudioSeconds = max(decodedAudioSeconds, segment.endSeconds)
            lastTranscriptUpdate = Date()
        }
    }

    func titleForWhisperModel(_ url: URL) -> String {
        switch url.lastPathComponent {
        case "ggml-large-v3-turbo-q5_0.bin": "Accuracy · Large v3 Turbo"
        case "ggml-small.en-q5_1.bin": "Balanced · Small English"
        case "ggml-base.en.bin": "Faster · Base English"
        default: url.lastPathComponent
        }
    }

    var isEnglishOnlyModel: Bool {
        guard let name = whisperModelURL()?.lastPathComponent else { return false }
        return name.contains(".en.") || name.contains(".en-")
    }

    var modelName: String {
        if selectedModelIsMissing { return "Missing: \(URL(fileURLWithPath: modelPath).lastPathComponent)" }
        return whisperModelURL()?.lastPathComponent ?? "No model selected"
    }

    func chooseModel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            if !availableWhisperModels.contains(url) { availableWhisperModels.append(url) }
            modelPath = url.path
            if isEnglishOnlyModel { transcriptionLanguage = TranscriptionLanguage.supported[0] }
        }
    }

    func whisperModelURL() -> URL? {
        if !modelPath.isEmpty {
            // An explicit choice whose file was deleted must not silently run another model.
            return selectedModelIsMissing ? nil : URL(fileURLWithPath: modelPath)
        }
        let models = availableWhisperModels
        for name in WhisperModelCatalog.preferredNames {
            if let model = models.first(where: { $0.lastPathComponent == name }) { return model }
        }
        return models.first
    }

    func transcriptBaseName() -> String {
        let rawName: String
        if let title = transcriptionSourceName, !title.isEmpty { rawName = title }
        else if transcriptionSource == .file { rawName = inputFile?.deletingPathExtension().lastPathComponent ?? "transcript" }
        else { rawName = "video" }
        return "\(OutputFiles.safeFileName(rawName))-transcript"
    }

    private func toolPath(_ name: String) -> String? {
        toolStatuses.first { $0.name == name }?.path
    }

    /// Log lines are buffered and published at most four times a second so chatty tools don't stall the UI.
    func appendLog(_ message: String) {
        guard !message.isEmpty else { return }
        pendingLog.append(message)
        guard !logFlushScheduled else { return }
        logFlushScheduled = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            self?.flushLog()
        }
    }

    func resetLog() {
        pendingLog.removeAll()
        logText = ""
    }

    func flushLog() {
        logFlushScheduled = false
        guard !pendingLog.isEmpty else { return }
        let joined = pendingLog.joined(separator: "\n")
        pendingLog.removeAll(keepingCapacity: true)
        let combined = logText.isEmpty ? joined : "\(logText)\n\(joined)"
        logText = combined.count > 100_000 ? String(combined.suffix(100_000)) : combined
    }
}
