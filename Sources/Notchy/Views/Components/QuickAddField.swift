import SwiftUI

/// Single-line task capture with a live preview of the parsed date and priority.
struct QuickAddField: View {
    var defaultDay: Date?
    var placeholder = "Add a task…"
    /// Only the main field inside the notch panel listens to ⌘N and dock dictation.
    var listensToShortcuts = true

    @Environment(\.isNotchPanel) private var isNotchPanel
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var speech: SpeechService

    @State private var text = ""
    @State private var dictationBase = ""
    @FocusState private var focused: Bool

    private var respondsToShortcuts: Bool { listensToShortcuts && isNotchPanel }

    private var preview: String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.count > 2 else { return nil }
        let parsed = NaturalLanguageParser.parse(trimmed)
        var parts: [String] = []
        if let due = parsed.dueDate { parts.append(DateText.due(due, hasTime: parsed.hasTime)) }
        if parsed.priority > .none { parts.append(parsed.priority.label) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(DS.inkSecondary)
                .accessibilityHidden(true)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused($focused)
                .onSubmit(submit)
                .accessibilityLabel("New task")
                .accessibilityHint("Type a task. Dates like tomorrow at 5pm are detected automatically.")
            if let preview {
                Label(preview, systemImage: "calendar.badge.clock")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .background(Capsule().fill(Color.white.opacity(0.55)))
                    .lineLimit(1)
                    .fixedSize()
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .accessibilityLabel("Detected: \(preview)")
            }
            MicButton(owner: "quickadd", onStart: { dictationBase = text }) { transcript, _ in
                text = dictationBase.isEmpty ? transcript : dictationBase + " " + transcript
                focused = true
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.07)))
        .animation(DS.snappy, value: preview)
        .onChange(of: state.focusQuickAddToken) {
            if respondsToShortcuts { focused = true }
        }
        .onChange(of: state.dictateToken) {
            guard respondsToShortcuts else { return }
            if !speech.isActive(owner: "quickadd") { dictationBase = text }
            speech.toggle(owner: "quickadd") { transcript, _ in
                text = dictationBase.isEmpty ? transcript : dictationBase + " " + transcript
                focused = true
            }
        }
    }

    private func submit() {
        speech.stop()
        guard let task = store.addTask(text: text, defaultDay: defaultDay) else { return }
        text = ""
        dictationBase = ""
        if let due = task.dueDate, task.hasTime {
            state.post(Nudge(symbol: "bell.badge.fill", title: "Reminder set", subtitle: "\(task.title) · \(DateText.due(due, hasTime: true))", tint: DS.Palette.tasks, sound: "Pop", duration: 2.5))
        }
    }
}
