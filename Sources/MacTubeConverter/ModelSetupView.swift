import SwiftUI

/// First-run prompt: one click downloads, verifies and installs the speech model.
struct ModelSetupSheet: View {
    @ObservedObject var model: AppModel
    @ObservedObject var downloader: ModelDownloader
    @Environment(\.dismiss) private var dismiss

    private var sizeText: String {
        ByteCountFormatter.string(fromByteCount: DownloadableModel.recommended.bytes, countStyle: .file)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Download the speech model?").font(.title2.weight(.semibold))
            Text("Transcription needs a Whisper speech model (\(sizeText), one-time download). MacTube fetches whisper.cpp's official Small English model from Hugging Face, checks it, and keeps it in ~/Library/Application Support/MacTubeConverter/Models. Downloading and converting videos work without it.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            switch downloader.state {
            case .idle:
                EmptyView()
            case .downloading(let fraction):
                ProgressView(value: fraction) { Text("Downloading… \(Int(fraction * 100))%").font(.caption) }
            case .verifying:
                HStack { ProgressView().controlSize(.small); Text("Checking the download…").font(.caption) }
            case .finished:
                Label("Speech model installed. Transcription is ready.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            HStack {
                if downloader.isWorking {
                    Button("Cancel Download") { downloader.cancel() }
                } else if case .finished = downloader.state {
                    EmptyView()
                } else {
                    Button("Not Now") { dismiss() }.keyboardShortcut(.cancelAction)
                }
                Spacer()
                if case .finished = downloader.state {
                    Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
                } else {
                    Button(downloader.state == .idle ? "Download" : "Try Again") { downloader.start() }
                        .keyboardShortcut(.defaultAction).disabled(downloader.isWorking)
                }
            }
        }
        .padding(28).frame(width: 500)
        .interactiveDismissDisabled(downloader.isWorking)
        .onReceive(downloader.$state) { state in
            if case .finished = state { Task { await model.refreshToolStatus() } }
        }
    }
}
