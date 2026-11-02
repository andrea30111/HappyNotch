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
                            Button("Open in Notes") {
                                if notesSync.selectedLibraryNoteID != nil {
                                    notesSync.openLibraryNoteInNotes()
                                } else {
                                    notesSync.openInNotes(state.notepadDay)
                                }
                            }
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
                Text(heading.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DS.inkSecondary)
                    .lineLimit(1)
                Rectangle().fill(DS.hairline).frame(height: 1)
                if notesSync.selectedLibraryNoteID != nil {
                    libraryNote
                } else {
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
    }

    private var heading: String {
        if notesSync.selectedLibraryNoteID != nil {
            return notesSync.selectedLibraryTitle ?? "Note"
        }
        return state.notepadDay.formatted(.dateTime.day().month(.abbreviated).year())
    }

    private var libraryNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(showsIndicators: false) {
                if let body = notesSync.selectedLibraryText {
                    Text(body.isEmpty ? "This note has no text." : body)
                        .font(.system(size: 13))
                        .foregroundStyle(body.isEmpty ? DS.inkTertiary : DS.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel("Loading note")
                }
            }
            HStack {
                Text("From Apple Notes")
                    .font(.system(size: 10.5))
                    .foregroundStyle(DS.inkSecondary)
                Spacer(minLength: 0)
                Button("Open in Notes") { notesSync.openLibraryNoteInNotes() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(DS.ink)
            }
        }
    }

    private func shift(_ days: Int) {
        notesSync.clearLibrarySelection()
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
                .help("Allow HappyNotch to control Notes in System Settings › Privacy & Security › Automation")
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

/// Daily pages plus every note in Apple Notes, newest first.
struct NotesHistoryCard: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var notesSync: AppleNotesSync

    private struct Page: Identifiable {
        var id: String
        var title: String
        var subtitle: String
        var sort: Date
        var day: Date?
        var noteID: String?
        var noteTitle: String?
    }

    private var pages: [Page] {
        let localDays = Set(store.notes.keys)
        var rows: [Page] = store.notes.keys.compactMap { key in
            guard let day = DayKey.date(from: key) else { return nil }
            let preview = store.note(for: day).prefix(80).replacingOccurrences(of: "\n", with: " ")
            return Page(id: "day-\(key)", title: DateText.relativeDay(day), subtitle: String(preview), sort: day, day: day, noteID: nil, noteTitle: nil)
        }
        for note in notesSync.library {
            if let day = NotesScript.day(fromTitle: note.title), localDays.contains(day) { continue }
            rows.append(Page(
                id: note.id,
                title: note.title,
                subtitle: note.modified.formatted(date: .abbreviated, time: .shortened),
                sort: note.modified,
                day: nil,
                noteID: note.id,
                noteTitle: note.title
            ))
        }
        return rows.sorted { $0.sort > $1.sort }
    }

    var body: some View {
        Card(tint: DS.Palette.notes.opacity(0.85)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    CardTitle(title: "Pages", symbol: "books.vertical")
                    Spacer(minLength: 0)
                    if notesSync.libraryLoading {
                        ProgressView().controlSize(.mini).accessibilityLabel("Loading Notes")
                    }
                }
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(pages) { page in
                            let selected = page.noteID != nil
                                ? notesSync.selectedLibraryNoteID == page.noteID
                                : notesSync.selectedLibraryNoteID == nil && page.day.map { Calendar.current.isDate($0, inSameDayAs: state.notepadDay) } == true
                            Button {
                                if let id = page.noteID, let title = page.noteTitle {
                                    notesSync.showLibraryNote(id: id, title: title)
                                } else if let day = page.day {
                                    notesSync.clearLibrarySelection()
                                    state.notepadDay = day
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(page.title)
                                        .font(.system(size: 12, weight: .semibold))
                                        .lineLimit(1)
                                    if !page.subtitle.isEmpty {
                                        Text(page.subtitle)
                                            .font(.system(size: 11))
                                            .foregroundStyle(DS.inkSecondary)
                                            .lineLimit(2)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(selected ? 0.55 : 0.25)))
                            }
                            .buttonStyle(.plain)
                        }
                        if let error = notesSync.libraryError {
                            Button(notesSync.needsPermission ? "Allow Notes" : "Try again") {
                                if notesSync.needsPermission {
                                    notesSync.openAutomationSettings()
                                } else {
                                    notesSync.refreshLibrary(launching: true)
                                }
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .medium))
                            .help(error)
                        }
                        if pages.isEmpty && !notesSync.libraryLoading {
                            Text(notesSync.libraryError ?? "Notes from Apple Notes show up here, along with your daily pages.")
                                .font(.system(size: 12))
                                .foregroundStyle(DS.inkTertiary)
                        }
                    }
                }
            }
        }
        .task { notesSync.refreshLibrary(launching: true) }
    }
}
