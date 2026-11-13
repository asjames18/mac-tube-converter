import CryptoKit
import Foundation

/// A Whisper model the app can fetch on first run.
struct DownloadableModel: Sendable, Equatable {
    let fileName: String
    let url: URL
    let sha256: String
    let bytes: Int64

    /// The app's preferred "Balanced · Small English" model (whisper.cpp's official ggml file).
    static let recommended = DownloadableModel(
        fileName: "ggml-small.en-q5_1.bin",
        url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en-q5_1.bin")!,
        sha256: "bfdff4894dcb76bbf647d56263ea2a96645423f1669176f4844a1bf8e478ad30",
        bytes: 190_098_681
    )
}

enum ModelInstallError: LocalizedError, Equatable {
    case sizeMismatch(expected: Int64, actual: Int64)
    case checksumMismatch

    var errorDescription: String? {
        switch self {
        case .sizeMismatch(let expected, let actual): "Download was incomplete (\(actual) of \(expected) bytes)."
        case .checksumMismatch: "Downloaded model failed its checksum and was discarded."
        }
    }
}

enum ModelInstaller {
    static func destinationFolder(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library/Application Support/MacTubeConverter/Models", isDirectory: true)
    }

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 * 1024 * 1024), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Verifies a downloaded file and moves it into `folder`. A file that fails is deleted.
    static func install(staged: URL, model: DownloadableModel, into folder: URL) throws -> URL {
        let fileManager = FileManager.default
        do {
            let size = (try fileManager.attributesOfItem(atPath: staged.path)[.size] as? NSNumber)?.int64Value ?? -1
            guard size == model.bytes else { throw ModelInstallError.sizeMismatch(expected: model.bytes, actual: size) }
            guard try sha256(of: staged) == model.sha256 else { throw ModelInstallError.checksumMismatch }
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = folder.appendingPathComponent(model.fileName)
            if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
            try fileManager.moveItem(at: staged, to: destination)
            return destination
        } catch {
            try? fileManager.removeItem(at: staged)
            throw error
        }
    }
}

/// Downloads the recommended model with progress. Only starts when the user clicks Download.
@MainActor
final class ModelDownloader: ObservableObject {
    enum State: Equatable {
        case idle
        case downloading(Double)
        case verifying
        case finished(URL)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    private var task: URLSessionDownloadTask?
    private var poll: Timer?
    private var cancelled = false

    var isWorking: Bool {
        switch state {
        case .downloading, .verifying: true
        default: false
        }
    }

    func start(_ model: DownloadableModel = .recommended, folder: URL = ModelInstaller.destinationFolder()) {
        guard !isWorking else { return }
        cancelled = false
        state = .downloading(0)
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("mactube-model-\(UUID().uuidString).part")
        let task = URLSession.shared.downloadTask(with: model.url) { [weak self] location, response, error in
            var message: String?
            if let error {
                message = error.localizedDescription
            } else if let status = (response as? HTTPURLResponse)?.statusCode, status != 200 {
                message = "The server returned HTTP \(status)."
            } else if let location {
                do { try FileManager.default.moveItem(at: location, to: staging) } catch { message = error.localizedDescription }
            } else {
                message = "No file was received."
            }
            let failure = message
            Task { @MainActor in self?.downloadEnded(staging: staging, failure: failure, model: model, folder: folder) }
        }
        self.task = task
        task.resume()
        poll = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let task = self.task, case .downloading = self.state else { return }
                let received = Double(task.countOfBytesReceived)
                self.state = .downloading(min(1, received / Double(model.bytes)))
            }
        }
    }

    func cancel() {
        cancelled = true
        task?.cancel()
    }

    private func downloadEnded(staging: URL, failure: String?, model: DownloadableModel, folder: URL) {
        poll?.invalidate()
        poll = nil
        task = nil
        if cancelled {
            try? FileManager.default.removeItem(at: staging)
            state = .idle
            return
        }
        if let failure {
            try? FileManager.default.removeItem(at: staging)
            state = .failed(failure)
            return
        }
        state = .verifying
        Task {
            let result: Result<URL, Error> = await Task.detached(priority: .userInitiated) {
                Result { try ModelInstaller.install(staged: staging, model: model, into: folder) }
            }.value
            switch result {
            case .success(let url): state = .finished(url)
            case .failure(let error): state = .failed(error.localizedDescription)
            }
        }
    }
}
