import SwiftUI

struct NotepadCard: View {
    var showsDayNavigation = false

    @EnvironmentObject private var store: Store
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var notesSync: AppleNotesSync
    @State private var dictationBase = ""

    private var text: Binding<String> {
        Binding(
            get: { store.note(for: state.notepadDay) },
            set: { store.setNote($0, for: state.notepadDay) }
        )
    }

    private var wordCount: Int {
        text.wrappedValue.split { $0.isWhitespace || $0.isNewline }.count
    }

    var body: some View {
        Card(tint: DS.Palette.notes) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    CardTitle(title: "Notepad", symbol: "square.and.pencil")
                    Spacer(minLength: 0)
                    if showsDayNavigation {
                        InkIconButton(symbol: "chevron.left", label: "Previous day") { shift(-1) }
                        InkIconButton(symbol: "chevron.right", label: "Next day") { shift(1) }
                    }
                    Menu {
                        Toggle("Sync with Apple Notes", isOn: Binding(
                            get: { store.settings.appleNotesSyncEnabled },
                            set: { notesSync.setEnabled($0) }
                        ))
                        if store.settings.appleNotesSyncEnabled {
                            Button("Open in Notes") { notesSync.openInNotes(state.notepadDay) }
                            Button("Sync Now") { notesSync.scheduleSync(after: 0, launchingNotes: true) }
                        }
                        Divider()
                        DashboardMenuItems(tool: .notepad)
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 11, weight: .bold))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .accessibilityLabel("Notepad options")
                }
                Text(state.notepadDay.formatted(.dateTime.day().month(.abbreviated).year()).uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DS.inkSecondary)
                Rectangle().fill(DS.hairline).frame(height: 1)
                ZStack(alignment: .topLeading) {
                    NoteEditor(text: text) { line in
                        store.addTask(text: line)
                        state.post(Nudge(symbol: "checklist", title: "Added to tasks", subtitle: line, tint: DS.Palette.tasks, sound: "Pop", duration: 2.5))
                    }
                    if text.wrappedValue.isEmpty {
                        Text("Jot something down…\n⌘↩ turns a line into a task.")
                            .font(.system(size: 13))
                            .foregroundStyle(DS.inkTertiary)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                HStack(spacing: 6) {
                    Label("\(wordCount) words", systemImage: "text.alignleft")
                        .labelStyle(CompactLabelStyle())
                        .font(.system(size: 10.5))
                        .foregroundStyle(DS.inkSecondary)
                    Spacer(minLength: 0)
                    NotesSyncStatus(day: state.notepadDay)
                    MicButton(owner: "notepad", onStart: { dictationBase = text.wrappedValue }) { transcript, _ in
                        let separator = dictationBase.isEmpty || dictationBase.hasSuffix("\n") ? "" : "\n"
                        text.wrappedValue = dictationBase + separator + transcript
                    }
                }
            }
        }
    }

    private func shift(_ days: Int) {
        state.notepadDay = Calendar.current.date(byAdding: .day, value: days, to: state.notepadDay) ?? state.notepadDay
    }
}

/// Small Apple Notes indicator in the notepad footer: syncing, synced (click to open), or needs attention.
private struct NotesSyncStatus: View {
    let day: Date
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var notesSync: AppleNotesSync

    var body: some View {
        if store.settings.appleNotesSyncEnabled {
            if notesSync.needsPermission {
                Button { notesSync.openAutomationSettings() } label: {
                    Label("Allow Notes", systemImage: "exclamationmark.triangle.fill")
                }
                .buttonStyle(.plain)
                .help("Allow Notchy to control Notes in System Settings › Privacy & Security › Automation")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.orange)
            } else if let error = notesSync.lastError {
                Button { notesSync.scheduleSync(after: 0, launchingNotes: true) } label: {
                    Image(systemName: "exclamationmark.icloud")
                }
                .buttonStyle(.plain)
                .help("\(error) — click to retry")
                .accessibilityLabel("Notes sync failed. Retry")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
            } else if notesSync.isSyncing {
                ProgressView().controlSize(.mini)
                    .accessibilityLabel("Syncing with Notes")
            } else if notesSync.isLinked(day) {
                Button { notesSync.openInNotes(day) } label: {
                    Label("Notes", systemImage: "checkmark.icloud")
                }
                .buttonStyle(.plain)
                .help("Synced with Apple Notes — click to open")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(DS.inkSecondary)
            }
        }
    }
}

/// Past notepad pages, newest first.
struct NotesHistoryCard: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var state: AppState

    private var days: [Date] {
        store.notes.keys.compactMap(DayKey.date(from:)).sorted(by: >)
    }

    var body: some View {
        Card(tint: DS.Palette.notes.opacity(0.85)) {
            VStack(alignment: .leading, spacing: 8) {
                CardTitle(title: "Pages", symbol: "books.vertical")
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(days, id: \.self) { day in
                            let selected = Calendar.current.isDate(day, inSameDayAs: state.notepadDay)
                            Button {
                                state.notepadDay = day
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(DateText.relativeDay(day))
                                        .font(.system(size: 12, weight: .semibold))
                                    Text(store.note(for: day).prefix(80).replacingOccurrences(of: "\n", with: " "))
                                        .font(.system(size: 11))
                                        .foregroundStyle(DS.inkSecondary)
                                        .lineLimit(2)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(selected ? 0.55 : 0.25)))
                            }
                            .buttonStyle(.plain)
                        }
                        if days.isEmpty {
                            Text("Your daily pages will show up here.")
                                .font(.system(size: 12))
                                .foregroundStyle(DS.inkTertiary)
                        }
                    }
                }
            }
        }
    }
}
