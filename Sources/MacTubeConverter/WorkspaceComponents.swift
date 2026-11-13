import AppKit
import SwiftUI

struct WorkspaceSection<Content: View>: View {
    let number: String
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Text(number).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(title).font(.headline)
            }
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
    }
}

struct FormatOption: View {
    let title: String
    let detail: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.callout.weight(.semibold)).foregroundStyle(.primary)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(selected ? Color.accentColor.opacity(0.07) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? Color.accentColor.opacity(0.7) : Color.secondary.opacity(0.2)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct RecentResultsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Recent results").font(.headline)
                Spacer()
                Text("This session").font(.caption).foregroundStyle(.secondary)
            }
            if model.recentResults.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray").font(.system(size: 28, weight: .light))
                    Text("Your finished files appear here.").font(.callout)
                    Text("Open a result or find it in your destination folder.").font(.caption).multilineTextAlignment(.center)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                ForEach(model.recentResults.prefix(8)) { result in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: result.output == nil ? "exclamationmark.circle" : "checkmark.circle.fill")
                            .foregroundStyle(result.output == nil ? Color.orange : Color.green)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(result.operation == "Download" ? result.name : result.output?.lastPathComponent ?? result.name)
                                .font(.callout.weight(.medium)).lineLimit(2).help(result.name)
                            Text("\(result.operation) · \(result.message)")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            if let output = result.output {
                                HStack {
                                    Button("Open") { NSWorkspace.shared.open(output) }
                                    Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([output]) }
                                }.buttonStyle(.link).font(.caption)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    Divider()
                }
            }
        }
    }
}

struct ToolsSheet: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmUpdate = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Tools & transcription").font(.title2.weight(.semibold))
            Text("MacTube uses local media tools. Install missing tools, then refresh their status.")
                .foregroundStyle(.secondary)
            ForEach(model.toolStatuses) { status in
                HStack(alignment: .top) {
                    Image(systemName: status.isAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle")
                        .foregroundStyle(status.isAvailable ? Color.green : Color.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(status.name).font(.headline)
                        Text(status.path ?? "Not found").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        if let version = model.toolVersions[status.name] {
                            Text(versionText(version)).font(.caption)
                                .foregroundStyle(version.isOutdated ? Color.orange : Color.secondary)
                        }
                    }
                    Spacer()
                    if status.name == "yt-dlp" {
                        Button("Update yt-dlp…") { confirmUpdate = true }
                            .disabled(!model.canUpdateYtDlp)
                            .help("Runs brew upgrade yt-dlp")
                    }
                }
            }
            if model.isRunning && model.statusMessage.hasPrefix("Updating yt-dlp") {
                HStack { ProgressView().controlSize(.small); Text(model.statusMessage).font(.caption) }
            }
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Whisper model").font(.headline)
                    Text(model.modelName).foregroundStyle(model.selectedModelIsMissing ? Color.orange : Color.secondary)
                    Text("Models are read from MACTUBE_MODEL_DIR, ~/Library/Application Support/MacTubeConverter/Models, or ~/Documents/Mac Apps/Models.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Choose Model…") { model.chooseModel() }
            }
            HStack {
                Button("Refresh Tools") {
                    Task { await model.refreshToolStatus(); await model.refreshToolVersions() }
                }.disabled(model.isBusy)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(28).frame(width: 520)
        .task { await model.refreshToolVersions() }
        .confirmationDialog("Do you really want to do this action?", isPresented: $confirmUpdate) {
            Button("Update yt-dlp") { Task { await model.updateYtDlp() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("MacTube will run “brew upgrade yt-dlp” on this Mac. This needs an internet connection and replaces the installed yt-dlp.")
        }
    }

    private func versionText(_ version: ToolVersion) -> String {
        let installed = version.installed ?? "not from Homebrew"
        guard let latest = version.latest else { return "Installed \(installed)" }
        return version.isOutdated ? "Installed \(installed) · latest \(latest)" : "Installed \(installed) · up to date"
    }
}
