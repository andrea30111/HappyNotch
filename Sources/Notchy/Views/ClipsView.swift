import SwiftUI

struct ClipsView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var clips: ClipService
    @EnvironmentObject private var state: AppState

    var body: some View {
        HStack(spacing: 10) {
            Card(tint: DS.Palette.clips) {
                VStack(alignment: .leading, spacing: 8) {
                    CardTitle(title: "Clips", symbol: "camera.viewfinder")
                    Text("Capture part of your screen. Clips stay on this Mac.")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(ClipService.Mode.allCases) { mode in
                        Button {
                            state.captureClip(mode)
                        } label: {
                            Label(mode.label, systemImage: mode.symbol)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(InkCapsuleButtonStyle())
                        .help(mode == .region ? "Capture region (⇧⌘C)" : "Capture \(mode.label.lowercased())")
                    }
                    Spacer(minLength: 0)
                    Toggle("Copy to clipboard", isOn: $store.settings.copyClipsToClipboard)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11))
                    Button {
                        clips.openFolder()
                    } label: {
                        Label("Open folder", systemImage: "folder")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(DS.inkSecondary)
                }
            }
            .frame(width: 200)

            gallery
        }
    }

    private var gallery: some View {
        Group {
            if store.clips.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 28))
                    Text("Your recent captures will appear here.")
                        .font(.system(size: 12))
                }
                .foregroundStyle(.white.opacity(0.4))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                        ForEach(store.clips.sorted { $0.createdAt > $1.createdAt }) { clip in
                            ClipThumbnail(clip: clip)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous).fill(Color.white.opacity(0.05)))
    }
}

private struct ClipThumbnail: View {
    let clip: Clip
    @EnvironmentObject private var clips: ClipService
    @EnvironmentObject private var state: AppState
    @State private var image: NSImage?
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Color.white.opacity(0.08)
                    }
                }
                .frame(height: 90)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(hovering ? 0.4 : 0.1)))

                if hovering {
                    HStack(spacing: 4) {
                        HeaderIconButton(symbol: "arrow.up.forward.app", label: "Open") { clips.open(clip) }
                        HeaderIconButton(symbol: "folder", label: "Show in Finder") { clips.reveal(clip) }
                        HeaderIconButton(symbol: "trash", label: "Delete") { clips.delete(clip) }
                    }
                    .padding(6)
                    .transition(.opacity)
                }
            }
            Text(clip.createdAt.formatted(.relative(presentation: .named)))
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.5))
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(DS.snappy, value: hovering)
        .onTapGesture {
            clips.copy(clip)
            state.post(Nudge(symbol: "doc.on.clipboard", title: "Copied to clipboard", tint: DS.Palette.clips, sound: "Pop", duration: 2))
        }
        .onDrag { NSItemProvider(contentsOf: clips.url(for: clip)) ?? NSItemProvider() }
        .contextMenu {
            Button("Copy") { clips.copy(clip) }
            Button("Open") { clips.open(clip) }
            Button("Show in Finder") { clips.reveal(clip) }
            Divider()
            Button("Delete", role: .destructive) { clips.delete(clip) }
        }
        .task(id: clip.id) {
            image = await Thumbnailer.thumbnail(for: clips.url(for: clip))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Clip from \(clip.createdAt.formatted(date: .abbreviated, time: .shortened))")
        .accessibilityHint("Activate to copy to the clipboard")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { clips.copy(clip) }
        .accessibilityAction(named: "Open") { clips.open(clip) }
        .accessibilityAction(named: "Delete") { clips.delete(clip) }
    }
}
