import SwiftUI

struct ClipboardView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", text = "Text", links = "Links", images = "Images", files = "Files"
        var id: String { rawValue }

        func matches(_ kind: ClipboardItem.Kind) -> Bool {
            switch self {
            case .all: return true
            case .text: return kind == .text
            case .links: return kind == .link
            case .images: return kind == .image
            case .files: return kind == .file
            }
        }
    }

    @EnvironmentObject private var clipboard: ClipboardHistory
    @EnvironmentObject private var store: Store
    @State private var query = ""
    @State private var filter: Filter = .all

    private var visible: [ClipboardItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let filtered = clipboard.items.filter { item in
            filter.matches(item.kind) && (q.isEmpty || (item.text ?? "").localizedCaseInsensitiveContains(q) || (item.sourceApp ?? "").localizedCaseInsensitiveContains(q))
        }
        return filtered.filter(\.isPinned) + filtered.filter { !$0.isPinned }
    }

    var body: some View {
        Card(tint: DS.Palette.clipboard) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    CardTitle(title: "Clipboard", symbol: "doc.on.clipboard")
                    Text("\(clipboard.items.count)/\(ClipboardHistory.limit)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DS.inkSecondary)
                    Spacer(minLength: 8)
                    PillSegment(options: Filter.allCases.map { .init(value: $0, title: $0.rawValue) }, selection: $filter)
                    HStack(spacing: 5) {
                        Image(systemName: "magnifyingglass").font(.system(size: 10, weight: .semibold))
                        TextField("Search", text: $query)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .accessibilityLabel("Search clipboard history")
                    }
                    .padding(.horizontal, 8)
                    .frame(width: 170, height: 24)
                    .background(Capsule().fill(Color.black.opacity(0.07)))
                    Menu {
                        Button("Clear History (Keep Pinned)") { clipboard.clear(keepPinned: true) }
                        Button("Clear Everything", role: .destructive) { clipboard.clear(keepPinned: false) }
                        Divider()
                        Toggle("Record Clipboard", isOn: $store.settings.clipboardHistoryEnabled)
                        Divider()
                        DashboardMenuItems(tool: .clipboard)
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 11, weight: .bold))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .accessibilityLabel("Clipboard options")
                }

                if !store.settings.clipboardHistoryEnabled {
                    emptyState(symbol: "pause.circle", text: "Clipboard history is paused.", action: ("Resume", { store.settings.clipboardHistoryEnabled = true }))
                } else if visible.isEmpty {
                    emptyState(symbol: "doc.on.clipboard", text: clipboard.items.isEmpty ? "Copy something and it shows up here." : "No matches.", action: nil)
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 8)], spacing: 8) {
                            ForEach(visible) { ClipboardTile(item: $0) }
                        }
                    }
                }
            }
        }
    }

    private func emptyState(symbol: String, text: String, action: (String, () -> Void)?) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 22))
            Text(text).font(.system(size: 12))
            if let action {
                Button(action.0, action: action.1).buttonStyle(InkCapsuleButtonStyle())
            }
        }
        .foregroundStyle(DS.inkTertiary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ClipboardTile: View {
    let item: ClipboardItem

    @EnvironmentObject private var clipboard: ClipboardHistory
    @EnvironmentObject private var state: AppState
    @State private var hovering = false
    @State private var image: NSImage?

    private var symbol: String {
        switch item.kind {
        case .text: return "text.alignleft"
        case .link: return "link"
        case .image: return "photo"
        case .file: return "doc"
        }
    }

    private var preview: String {
        switch item.kind {
        case .file:
            return (item.text ?? "").split(separator: "\n").map { URL(fileURLWithPath: String($0)).lastPathComponent }.joined(separator: ", ")
        default:
            return (item.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    var body: some View {
        Button(action: copy) {
            VStack(alignment: .leading, spacing: 6) {
                Group {
                    if item.kind == .image {
                        Group {
                            if let image {
                                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                            } else {
                                Color.black.opacity(0.06)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    } else {
                        Text(preview)
                            .font(.system(size: 12, design: item.kind == .text ? .default : .monospaced))
                            .foregroundStyle(item.kind == .link ? Color.blue.opacity(0.85) : DS.ink)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, minHeight: 46, alignment: .topLeading)
                    }
                }
                HStack(spacing: 4) {
                    Image(systemName: item.isPinned ? "pin.fill" : symbol)
                    Text([item.sourceApp, item.createdAt.formatted(.relative(presentation: .named))].compactMap { $0 }.joined(separator: " · "))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .font(.system(size: 10))
                .foregroundStyle(DS.inkSecondary)
            }
            .padding(9)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(hovering ? 0.6 : 0.38)))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if hovering {
                HStack(spacing: 0) {
                    InkIconButton(symbol: item.isPinned ? "pin.slash" : "pin", label: item.isPinned ? "Unpin" : "Pin", size: 20) { clipboard.togglePin(item) }
                    InkIconButton(symbol: "xmark", label: "Remove", size: 20) { clipboard.delete(item) }
                }
                .padding(4)
                .background(Capsule().fill(Color.white.opacity(0.85)))
                .padding(5)
                .transition(.opacity)
            }
        }
        .onHover { hovering = $0 }
        .animation(DS.snappy, value: hovering)
        .contextMenu {
            Button("Copy") { copy() }
            Button(item.isPinned ? "Unpin" : "Pin") { clipboard.togglePin(item) }
            Divider()
            Button("Remove", role: .destructive) { clipboard.delete(item) }
        }
        .task(id: item.id) {
            if item.kind == .image, let url = clipboard.imageURL(for: item) {
                image = await Thumbnailer.thumbnail(for: url, maxPixelSize: 400)
            }
        }
        .help("Click to copy")
        .accessibilityLabel("\(item.kind.rawValue): \(item.kind == .image ? "image" : preview)")
        .accessibilityHint("Copies to the clipboard")
        .accessibilityAction(named: item.isPinned ? "Unpin" : "Pin") { clipboard.togglePin(item) }
        .accessibilityAction(named: "Remove") { clipboard.delete(item) }
    }

    private func copy() {
        clipboard.copy(item)
        state.post(Nudge(symbol: "doc.on.clipboard.fill", title: "Copied", subtitle: item.kind == .image ? "Image" : String(preview.prefix(60)), tint: DS.Palette.clipboard, sound: "Pop", duration: 1.8))
    }
}
