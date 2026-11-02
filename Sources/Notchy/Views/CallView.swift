import SwiftUI

/// Records a Teams call open on this Mac. The file is audio only and stays on the machine.
struct CallView: View {
    @EnvironmentObject private var calls: CallRecorder
    @EnvironmentObject private var permissions: PermissionsCenter

    var body: some View {
        HStack(spacing: 10) {
            Card(tint: DS.Palette.call) {
                VStack(alignment: .leading, spacing: 10) {
                    CardTitle(title: "Call", symbol: "phone.fill")
                    Text("Records your microphone and Teams audio. Only audio is saved. Teams does not tell the other people, so say so before you start.")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(calls.teamsRunning ? Color(red: 0.18, green: 0.55, blue: 0.28) : DS.inkTertiary)
                            .frame(width: 7, height: 7)
                        Text(calls.teamsRunning ? "Teams is open" : "Teams is not open")
                            .font(.system(size: 11, weight: .medium))
                    }
                    Spacer(minLength: 0)
                    if calls.isRecording {
                        Text(calls.elapsedText)
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }
                    Button {
                        Task {
                            await calls.toggle()
                            permissions.refresh()
                        }
                    } label: {
                        Label(buttonTitle, systemImage: calls.isRecording ? "stop.fill" : "record.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(InkCapsuleButtonStyle(prominent: true))
                    .disabled(calls.phase == .preparing || calls.phase == .saving)
                    if let lastError = calls.lastError {
                        Text(lastError)
                            .font(.system(size: 11))
                            .foregroundStyle(DS.danger)
                            .fixedSize(horizontal: false, vertical: true)
                        if let hint = calls.permissionHint {
                            Button("Open Settings") { permissions.openSettings(hint) }
                                .buttonStyle(.plain)
                                .font(.system(size: 11, weight: .semibold))
                        }
                    }
                }
            }
            .frame(width: 280)

            recordings
        }
        .onAppear {
            calls.refreshPresence()
            calls.reload()
        }
    }

    private var buttonTitle: String {
        switch calls.phase {
        case .idle: return "Record call"
        case .preparing: return "Starting…"
        case .recording: return "Stop"
        case .saving: return "Saving…"
        }
    }

    private var recordings: some View {
        Group {
            if calls.recordings.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.system(size: 28))
                    Text(calls.phase == .saving ? "Saving the recording…" : "Recordings stay on this Mac.")
                        .font(.system(size: 12))
                }
                .foregroundStyle(.white.opacity(0.4))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(calls.recordings) { recording in
                            CallRecordingRow(recording: recording)
                        }
                    }
                    .padding(12)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous).fill(Color.white.opacity(0.05)))
    }
}

private struct CallRecordingRow: View {
    let recording: CallRecording
    @EnvironmentObject private var calls: CallRecorder

    private var isPlaying: Bool { calls.playingURL == recording.url }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(recording.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 12, weight: .semibold))
                Text(CallRecorder.format(recording.duration))
                    .font(.system(size: 11, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer(minLength: 0)
            rowButton(isPlaying ? "stop.fill" : "play.fill", label: isPlaying ? "Stop" : "Play") {
                calls.togglePlayback(recording)
            }
            rowButton("folder", label: "Show in Finder") { calls.reveal(recording) }
            rowButton("trash", label: "Delete") { calls.delete(recording) }
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
        .foregroundStyle(.white)
    }

    private func rowButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }
}
