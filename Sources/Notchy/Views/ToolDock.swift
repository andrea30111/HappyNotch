import SwiftUI

/// Row of floating round icons under the open notch panel, one per tool,
/// plus quick actions for dictation and screen capture.
struct ToolDock: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var speech: SpeechService
    @EnvironmentObject private var clips: ClipService
    @EnvironmentObject private var calls: CallRecorder

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(Tool.allCases.enumerated()), id: \.element) { index, tool in
                DockButton(
                    symbol: tool.symbol,
                    label: tool.title,
                    shortcut: tool.shortcut,
                    tint: tool.tint,
                    isSelected: state.tool == tool || (tool == .call && calls.isRecording),
                    index: index
                ) {
                    withAnimation(DS.spring) { state.tool = tool }
                }
            }

            Capsule()
                .fill(Color.white.opacity(0.18))
                .frame(width: 1.5, height: 24)
                .padding(.horizontal, 2)
                .accessibilityHidden(true)

            DockButton(
                symbol: speech.isActive(owner: "quickadd") ? "waveform" : "mic.fill",
                label: speech.isActive(owner: "quickadd") ? "Stop dictation" : "Dictate a task",
                shortcut: "⇧⌘M",
                tint: DS.Palette.voice,
                isSelected: speech.isActive(owner: "quickadd"),
                index: Tool.allCases.count
            ) {
                state.startDictation()
            }

            DockButton(
                symbol: "camera.aperture",
                label: "Capture a clip",
                shortcut: "⇧⌘C",
                tint: DS.Palette.clips,
                isSelected: clips.isCapturing,
                index: Tool.allCases.count + 1
            ) {
                state.captureClip(.region)
            }
        }
        .frame(height: NotchLayout.dockHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tools")
    }
}

private struct DockButton: View {
    let symbol: String
    let label: String
    let shortcut: String
    let tint: Color
    let isSelected: Bool
    let index: Int
    let action: () -> Void

    @State private var hovering = false
    @State private var appeared = false
    @State private var floating = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isSelected ? Color.black.opacity(0.8) : tint)
                .frame(width: 44, height: 44)
                .background {
                    Circle().fill(isSelected ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(Color.black.opacity(0.9)))
                }
                .overlay {
                    Circle().strokeBorder(Color.white.opacity(hovering ? 0.28 : 0.1), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.45), radius: hovering ? 12 : 8, y: hovering ? 7 : 4)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .scaleEffect(hovering ? 1.12 : 1)
        .offset(y: hovering ? 3 : (floating ? -1.5 : 1.5))
        .overlay(alignment: .bottom) {
            if hovering {
                HStack(spacing: 4) {
                    Text(label).fontWeight(.semibold)
                    Text(shortcut).foregroundStyle(.white.opacity(0.5))
                }
                .font(.system(size: 10))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .frame(height: 20)
                .background(Capsule().fill(Color.black.opacity(0.92)))
                .fixedSize()
                .offset(y: 28)
                .transition(.opacity.combined(with: .offset(y: -4)))
                .allowsHitTesting(false)
            }
        }
        .offset(y: appeared ? 0 : -26)
        .opacity(appeared ? 1 : 0)
        .animation(DS.snappy, value: hovering)
        .onHover { hovering = $0 }
        .onAppear {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.68).delay(Double(index) * 0.022)) {
                appeared = true
            }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true).delay(Double(index) * 0.15)) {
                floating = true
            }
        }
        .help("\(label) (\(shortcut))")
        .accessibilityLabel(label)
        .accessibilityHint("Shortcut \(shortcut)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
