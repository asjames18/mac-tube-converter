import SwiftUI

struct TranscriptionProgressView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 10) {
                if let progress = model.transcriptionProgress {
                    ProgressView(value: progress)
                    Text("\(Int(progress * 100))% decoded").font(.callout.weight(.medium))
                } else {
                    ProgressView().controlSize(.small)
                }
                if let start = model.transcriptionStartedAt {
                    Text("Elapsed \(time(context.date.timeIntervalSince(start))) · Audio \(time(model.decodedAudioSeconds)) / \(model.transcriptionAudioDuration.map(time) ?? "—")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let last = model.lastTranscriptUpdate, context.date.timeIntervalSince(last) > 45 {
                    Text("Decoding the next section. Progress can pause during difficult audio; Cancel remains available.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func time(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
