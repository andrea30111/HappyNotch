import SwiftUI

struct MicButton: View {
    let owner: String
    var onStart: () -> Void = {}
    let onText: (String, Bool) -> Void

    @EnvironmentObject private var speech: SpeechService

    private var isActive: Bool { speech.isActive(owner: owner) }

    var body: some View {
        Button {
            if !isActive { onStart() }
            speech.toggle(owner: owner, onText: onText)
        } label: {
            Image(systemName: isActive ? "waveform" : "mic")
                .font(.system(size: 12, weight: .semibold))
                .symbolEffect(.variableColor.iterative, isActive: isActive)
                .foregroundStyle(isActive ? DS.danger : DS.inkSecondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isActive ? "Stop dictation" : "Dictate (on-device)")
        .accessibilityLabel(isActive ? "Stop dictation" : "Dictate")
    }
}
