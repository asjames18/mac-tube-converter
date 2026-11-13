import AppKit
import SwiftUI

struct SourceInputView: View {
    @ObservedObject var model: AppModel
    @State private var dropTargeted = false
    @State private var transcribeDropTargeted = false

    var body: some View {
        WorkspaceSection(number: "01", title: model.selectedTab == .convert ? "Add your media" : "Choose a source") {
            if model.selectedTab == .transcribe {
                Picker("Source", selection: $model.transcriptionSource) {
                    ForEach(TranscriptionSource.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
            }
            if model.selectedTab == .convert {
                conversionFiles
            } else if model.selectedTab == .transcribe && model.transcriptionSource == .file {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 14) {
                        Image(systemName: "waveform").font(.title).foregroundStyle(.tint)
                        Text(model.inputFile?.lastPathComponent ?? "Drop an audio or video file here, or choose one")
                            .lineLimit(2).truncationMode(.middle)
                        Spacer()
                        Button("Choose File…") { model.chooseInputFile() }
                    }
                    .padding(12)
                    .background(transcribeDropTargeted ? Color.accentColor.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor.opacity(transcribeDropTargeted ? 0.8 : 0.25), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                    .dropDestination(for: URL.self) { urls, _ in
                        guard !model.isBusy, let url = urls.first else { return false }
                        return model.setTranscriptionFile(url)
                    } isTargeted: { transcribeDropTargeted = $0 }
                    if let message = model.inputMessage {
                        Text(message).font(.caption).foregroundStyle(.orange)
                    }
                }
            } else {
                linkInput
            }
        }.disabled(model.isBusy)
    }

    private var linkInput: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(model.selectedTab == .download ? "Video links · one per line" : "Video link")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button { 
                    if let text = NSPasteboard.general.string(forType: .string) {
                        model.pasteLinks(text)
                    }
                } label: { Label("Paste", systemImage: "doc.on.clipboard") }
            }
            TextEditor(text: $model.videoURL)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: model.selectedTab == .download ? 80 : 40)
                .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topLeading) {
                    if model.videoURL.isEmpty {
                        Text("https://www.youtube.com/watch?v=…")
                            .font(.system(.body, design: .monospaced)).foregroundStyle(.tertiary)
                            .padding(13).allowsHitTesting(false)
                    }
                }
                .accessibilityLabel("Video links")
            if model.selectedTab == .download {
                HStack {
                    Text("\(model.downloadLinks.count) link\(model.downloadLinks.count == 1 ? "" : "s")")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Toggle("Single video per link", isOn: $model.singleVideoOnly).toggleStyle(.checkbox)
                }
            }
        }
    }

    private var conversionFiles: some View {
        VStack(spacing: 14) {
            VStack(spacing: 10) {
                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.system(size: 30, weight: .light)).foregroundStyle(.tint)
                Text("Drop audio or video files here").font(.callout.weight(.medium))
                Button(model.queuedFiles.isEmpty ? "Choose Files…" : "Add More Files…") { model.chooseConversionFiles() }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 22)
            .background(dropTargeted ? Color.accentColor.opacity(0.1) : Color.accentColor.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor.opacity(dropTargeted ? 0.8 : 0.3), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
            .dropDestination(for: URL.self) { urls, _ in
                guard !model.isBusy else { return false }
                model.addFiles(urls)
                return true
            } isTargeted: { dropTargeted = $0 }
            if !model.queuedFiles.isEmpty {
                HStack {
                    Text("\(model.queuedFiles.count) files in queue").font(.caption.weight(.medium))
                    Spacer()
                    Button("Clear") { model.queuedFiles.removeAll() }.buttonStyle(.link)
                }.foregroundStyle(.secondary)
                ForEach(model.queuedFiles, id: \.self) { file in
                    HStack(spacing: 10) {
                        Image(systemName: "doc")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(file.lastPathComponent).font(.callout).lineLimit(1).truncationMode(.middle)
                            Text(fileInfo(file)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { model.queuedFiles.removeAll { $0 == file } } label: {
                            Image(systemName: "xmark").font(.caption)
                        }.buttonStyle(.borderless).help("Remove \(file.lastPathComponent)")
                    }
                }
            }
            if let message = model.inputMessage {
                Text(message).font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private func fileInfo(_ url: URL) -> String {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return "\(url.pathExtension.uppercased()) · \(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))"
    }
}
