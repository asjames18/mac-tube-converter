import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var showTools = false
    @State private var showActivity = false

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "play.rectangle.fill").font(.title2).foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("MacTube").font(.headline)
                        Text("Media workspace").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(20)
                List(selection: Binding<AppTab?>(get: { model.selectedTab }, set: { if let tab = $0 { model.selectedTab = tab } })) {
                    Section("WORKSPACE") {
                        ForEach(AppTab.allCases) { tab in
                            Label(tab.title, systemImage: tab.symbol).padding(.vertical, 5).tag(tab)
                        }
                    }
                }.listStyle(.sidebar).disabled(model.isBusy)
                VStack(alignment: .leading, spacing: 14) {
                    Label("Processed on your Mac", systemImage: "desktopcomputer")
                        .font(.caption).foregroundStyle(.secondary)
                    Button { showTools = true } label: {
                        Label("Tools & transcription", systemImage: "slider.horizontal.3")
                    }.buttonStyle(.plain).disabled(model.isBusy)
                }.padding(20)
            }.navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            VStack(spacing: 0) {
                ScrollView {
                    HStack(alignment: .top, spacing: 24) {
                        VStack(alignment: .leading, spacing: 20) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(model.selectedTab.title).font(.system(size: 30, weight: .semibold))
                                Text(model.selectedTab.subtitle).foregroundStyle(.secondary)
                            }.padding(.bottom, 4)
                            SourceInputView(model: model)
                            formatSection.disabled(model.isBusy)
                            destinationSection.disabled(model.isBusy)
                            if model.selectedTab == .transcribe && !model.transcriptText.isEmpty { transcriptSection }
                        }.frame(maxWidth: 720, alignment: .leading)
                        VStack(alignment: .leading, spacing: 24) {
                            summary
                            Divider()
                            RecentResultsView(model: model)
                        }.frame(width: 240).padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(28)
                }
                Divider()
                actionBar
                if showActivity {
                    Divider()
                    ScrollView {
                        Text(model.logText.isEmpty ? "Job details will appear here." : model.logText)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled).padding(16)
                    }.frame(height: 150)
                }
            }
            .navigationTitle("MacTube Converter")
            .toolbar {
                ToolbarItem {
                    Button { showActivity.toggle() } label: { Label("Activity", systemImage: "terminal") }
                        .help("Show or hide job details")
                }
            }
        }
        .sheet(isPresented: $showTools) { ToolsSheet(model: model) }
        .sheet(isPresented: $model.showModelSetup) { ModelSetupSheet(model: model, downloader: model.modelDownloader) }
        .task { await model.refreshToolStatus() }
    }

    private var formatSection: some View {
        WorkspaceSection(number: "02", title: model.selectedTab == .transcribe ? "Transcript options" : "Choose your format") {
            if model.selectedTab == .download {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(DownloadFormat.allCases) { format in
                        FormatOption(title: format.title, detail: format.detail, selected: model.downloadFormat == format) {
                            model.downloadFormat = format
                        }
                    }
                }
            } else if model.selectedTab == .convert {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(ConversionFormat.allCases) { format in
                        FormatOption(title: format.title, detail: format.detail, selected: model.conversionFormat == format) {
                            model.conversionFormat = format
                        }
                    }
                }
                if model.conversionFormat.supportsQuality {
                    Divider()
                    Picker("Quality", selection: $model.conversionQuality) {
                        ForEach(ConversionQuality.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented)
                    Text("Compact saves space. High keeps more detail and creates larger files.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Picker("Speech model", selection: $model.modelPath) {
                    Text("Automatic · balanced model").tag("")
                    ForEach(model.availableWhisperModels, id: \.path) { file in
                        Text(model.titleForWhisperModel(file)).tag(file.path)
                    }
                }
                Text("Balanced is recommended for this Mac. Accuracy uses the larger Turbo model and takes much longer. Singing and background music may still need corrections.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Language", selection: $model.transcriptionLanguage) {
                    ForEach(TranscriptionLanguage.supported) { Text($0.title).tag($0) }
                }.disabled(model.isEnglishOnlyModel)
                if model.isEnglishOnlyModel {
                    Text("English model selected. Choose a multilingual model in Tools for automatic language detection.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                TextField("Optional names or terminology to recognize", text: $model.transcriptionVocabulary)
                    .textFieldStyle(.roundedBorder)
                Toggle("Extra decoding retries", isOn: $model.extraTranscriptionRetries)
                Text("Optional alternate attempts for difficult passages. These can pause progress for several minutes, especially with music.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Export SRT subtitles alongside the text", isOn: $model.exportSubtitles)
            }
        }
    }

    private var destinationSection: some View {
        WorkspaceSection(number: "03", title: "Save to") {
            HStack(spacing: 12) {
                Image(systemName: "folder.fill").font(.title2).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.outputFolder?.lastPathComponent ?? "Choose a folder").font(.callout.weight(.medium))
                    Text(model.outputFolder?.path ?? "No destination selected")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        .help(model.outputFolder?.path ?? "")
                }
                Spacer()
                Button("Change…") { model.chooseOutputFolder() }
            }
            Text("Existing files are kept. New conversions receive a numbered filename when needed.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("AT A GLANCE").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Label(model.selectedTab.title, systemImage: model.selectedTab.symbol).font(.title3.weight(.medium))
            summaryRow("Source", model.selectedTab == .convert ? "\(model.queuedFiles.count) files" : model.selectedTab == .transcribe && model.transcriptionSource == .file ? "Local file" : "\(model.downloadLinks.count) links")
            summaryRow("Output", model.selectedTab == .convert ? model.conversionFormat.title : model.selectedTab == .download ? model.downloadFormat.title : model.exportSubtitles ? "TXT + SRT" : "TXT")
            summaryRow("Destination", model.outputFolder?.lastPathComponent ?? "Not selected")
            if model.isBusy {
                if model.selectedTab == .transcribe && model.transcriptionProgress != nil { TranscriptionProgressView(model: model) }
                else if let progress = model.jobProgress {
                    ProgressView(value: progress)
                    Text("\(Int(progress * 100))%").font(.callout.weight(.medium))
                } else if model.selectedTab == .transcribe { TranscriptionProgressView(model: model) }
                else { ProgressView() }
                Text(model.statusMessage).font(.callout).foregroundStyle(.secondary)
                if model.batchRunning { Text("Item \(model.batchPosition) of \(model.batchCount)").font(.caption).foregroundStyle(.secondary) }
            } else {
                Text(model.readinessMessage ?? "Everything is ready. Start when you are.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if model.suggestYtDlpUpdate {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("yt-dlp may be out of date", systemImage: "arrow.triangle.2.circlepath").font(.callout.weight(.medium))
                        Text("Sites change often. Updating yt-dlp usually fixes this error.").font(.caption).foregroundStyle(.secondary)
                        Button("Open Tools…") { showTools = true }
                    }
                    .padding(10)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private func summaryRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing).lineLimit(2)
        }.font(.callout)
    }

    private var actionBar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.isBusy ? model.statusMessage : model.statusMessage == "Ready" ? "Ready when you are" : model.statusMessage)
                    .font(.callout.weight(.medium)).lineLimit(1)
                Text(model.isBusy ? "You can cancel at any time." : "⌘ Return to start · Results stay in your chosen folder")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if model.isBusy {
                Button("Cancel") { model.cancelCurrentTask() }.keyboardShortcut(.cancelAction)
            }
            Button { Task { await model.startWorkspaceJob() } } label: {
                Label(actionTitle, systemImage: model.selectedTab.symbol).padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(model.isBusy || model.readinessMessage != nil)
        }.padding(.horizontal, 28).padding(.vertical, 16)
    }

    private var actionTitle: String {
        if model.isBusy { return "Working…" }
        switch model.selectedTab {
        case .convert: return model.queuedFiles.count > 1 ? "Convert \(model.queuedFiles.count) Files" : "Convert File"
        case .download: return model.downloadLinks.count > 1 ? "Download \(model.downloadLinks.count) Links" : "Start Download"
        case .transcribe: return "Create Transcript"
        }
    }

    private var transcriptSection: some View {
        WorkspaceSection(number: "04", title: "Your transcript") {
            HStack {
                Text(model.isBusy ? "Live preview · not saved yet" : model.statusMessage.hasPrefix("Transcript saved") ? "Saved and ready to use" : "Partial preview · not saved").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Copy Text") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.transcriptText, forType: .string)
                }
            }
            Text(model.transcriptText).textSelection(.enabled).font(.body).lineSpacing(5)
        }
    }
}
