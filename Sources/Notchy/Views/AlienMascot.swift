import SwiftUI

/// Notchy's mascot: a little alien head with big almond eyes that blink now and then.
/// Drawn in a 100×100 design space and scaled to `size`.
struct AlienMascot: View {
    var size: CGFloat = 20
    var blinks = true
    var headColor: Color = .white
    var eyeColor: Color = .black
    /// Punches the eyes out of the head instead of painting them (for template images).
    var eyesCutOut = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var eyeOpenness: CGFloat = 1

    var body: some View {
        let s = size / 100
        ZStack {
            AlienHeadShape().fill(headColor)
            Group {
                eye(angle: 28).offset(x: -17 * s, y: 8 * s)
                eye(angle: -28).offset(x: 17 * s, y: 8 * s)
            }
            .blendMode(eyesCutOut ? .destinationOut : .normal)
        }
        .compositingGroup()
        .frame(width: size, height: size)
        .task(id: blinks && !reduceMotion) {
            guard blinks, !reduceMotion else { return }
            await blinkLoop()
        }
        .accessibilityHidden(true)
    }

    private func eye(angle: Double) -> some View {
        let s = size / 100
        return Ellipse()
            .fill(eyeColor)
            .frame(width: 30 * s, height: 17 * s)
            .scaleEffect(x: 1, y: eyeOpenness, anchor: .center)
            .rotationEffect(.degrees(angle))
    }

    private func blinkLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(Int.random(in: 2400...5200)))
            guard !Task.isCancelled else { return }
            await blink()
            if Int.random(in: 0..<5) == 0 {
                try? await Task.sleep(for: .milliseconds(160))
                await blink()
            }
        }
    }

    private func blink() async {
        withAnimation(.easeIn(duration: 0.07)) { eyeOpenness = 0.08 }
        try? await Task.sleep(for: .milliseconds(110))
        withAnimation(.easeOut(duration: 0.12)) { eyeOpenness = 1 }
        try? await Task.sleep(for: .milliseconds(120))
    }
}

/// Wide domed cranium tapering to a small chin.
struct AlienHeadShape: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x / 100, y: rect.minY + rect.height * y / 100)
        }
        var path = Path()
        path.move(to: p(50, 97))
        path.addCurve(to: p(6, 42), control1: p(30, 95), control2: p(6, 70))
        path.addCurve(to: p(50, 3), control1: p(6, 16), control2: p(26, 3))
        path.addCurve(to: p(94, 42), control1: p(74, 3), control2: p(94, 16))
        path.addCurve(to: p(50, 97), control1: p(94, 70), control2: p(70, 95))
        path.closeSubpath()
        return path
    }
}

/// The app icon artwork: the mascot on a black squircle, following the macOS icon grid.
struct AppIconArtwork: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.17), Color(white: 0.02)], startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: 185, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 4)
                )
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.35), radius: 14, y: 10)
            AlienMascot(size: 540, blinks: false)
                .offset(y: 12)
        }
        .frame(width: 1024, height: 1024)
    }
}

extension AlienMascot {
    /// A menu bar template image of the mascot (black silhouette with see-through eyes).
    @MainActor
    static func templateImage(pointSize: CGFloat = 16) -> NSImage? {
        let renderer = ImageRenderer(content: AlienMascot(size: pointSize, blinks: false, headColor: .black, eyesCutOut: true))
        renderer.scale = 2
        guard let cgImage = renderer.cgImage else { return nil }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: pointSize, height: pointSize))
        image.isTemplate = true
        image.accessibilityDescription = AppInfo.name
        return image
    }
}
