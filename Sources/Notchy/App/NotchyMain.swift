import AppKit
import SwiftUI

enum AppInfo {
    static let name = "HappyNotch"
    static let bundleIdentifier = "app.notchy.Notchy"
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }
}

@main
enum NotchyMain {
    static func main() {
        if CommandLine.arguments.contains("--mcp-stdio") {
            MCPStdioBridge.run()
        }
        #if DEBUG
        if let index = CommandLine.arguments.firstIndex(of: "--render-icon"), index + 1 < CommandLine.arguments.count {
            MainActor.assumeIsolated { renderIconSet(to: URL(fileURLWithPath: CommandLine.arguments[index + 1])) }
            exit(0)
        }
        #endif
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let delegate = AppDelegate()
            app.delegate = delegate
            app.setActivationPolicy(.accessory)
            withExtendedLifetime(delegate) { app.run() }
        }
    }

    #if DEBUG
    /// Writes an `.iconset` folder for `iconutil -c icns` (see scripts/make-icon.sh).
    @MainActor
    private static func renderIconSet(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for points in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let renderer = ImageRenderer(content: AppIconArtwork())
                renderer.scale = CGFloat(points * scale) / 1024
                guard let cgImage = renderer.cgImage,
                      let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else { continue }
                let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
                try? png.write(to: directory.appendingPathComponent(name))
            }
        }
    }
    #endif
}
