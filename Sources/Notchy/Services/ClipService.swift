import AppKit
import ImageIO

@MainActor
final class ClipService: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case region, window, screen
        var id: String { rawValue }

        var label: String {
            switch self {
            case .region: return "Region"
            case .window: return "Window"
            case .screen: return "Full screen"
            }
        }

        var symbol: String {
            switch self {
            case .region: return "rectangle.dashed"
            case .window: return "macwindow"
            case .screen: return "display"
            }
        }

        var arguments: [String] {
            switch self {
            case .region: return ["-i"]
            case .window: return ["-i", "-W"]
            case .screen: return ["-m"]
            }
        }
    }

    @Published private(set) var isCapturing = false
    var onSaved: ((Clip) -> Void)?

    private let store: Store

    init(store: Store) {
        self.store = store
    }

    func url(for clip: Clip) -> URL {
        Store.clipsDirectory.appendingPathComponent(clip.fileName)
    }

    /// Uses the system `screencapture` tool so selection, window picking and the
    /// Screen Recording permission all behave exactly like ⌘⇧4.
    func capture(_ mode: Mode) {
        guard !isCapturing else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let fileName = "Clip \(formatter.string(from: Date())).png"
        let url = Store.clipsDirectory.appendingPathComponent(fileName)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = mode.arguments + ["-x", "-t", "png", url.path]
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.finishCapture(url: url, fileName: fileName) }
        }
        isCapturing = true
        do {
            try process.run()
        } catch {
            isCapturing = false
        }
    }

    private func finishCapture(url: URL, fileName: String) {
        isCapturing = false
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let clip = Clip(fileName: fileName)
        store.clips.insert(clip, at: 0)
        if store.settings.copyClipsToClipboard { copy(clip) }
        onSaved?(clip)
    }

    func copy(_ clip: Clip) {
        guard let image = NSImage(contentsOf: url(for: clip)) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image, url(for: clip) as NSURL])
    }

    func open(_ clip: Clip) {
        NSWorkspace.shared.open(url(for: clip))
    }

    func reveal(_ clip: Clip) {
        NSWorkspace.shared.activateFileViewerSelecting([url(for: clip)])
    }

    func openFolder() {
        NSWorkspace.shared.open(Store.clipsDirectory)
    }

    func delete(_ clip: Clip) {
        try? FileManager.default.removeItem(at: url(for: clip))
        Thumbnailer.cache.removeObject(forKey: url(for: clip) as NSURL)
        store.clips.removeAll { $0.id == clip.id }
    }
}

enum Thumbnailer {
    nonisolated(unsafe) static let cache = NSCache<NSURL, NSImage>()

    static func thumbnail(for url: URL, maxPixelSize: Int = 360) async -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        let cgImage = await Task.detached(priority: .utility) { () -> CGImage? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceCreateThumbnailWithTransform: true,
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }.value
        guard let cgImage else { return nil }
        let image = NSImage(cgImage: cgImage, size: .zero)
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}
