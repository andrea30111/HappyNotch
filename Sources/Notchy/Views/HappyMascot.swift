import SwiftUI

/// One frame of HappyNotch's face. The live icon morphs between these.
struct FaceExpression: Equatable {
    var leftOpen: CGFloat
    var rightOpen: CGFloat
    var smile: CGFloat
    var mouthOpen: CGFloat
    var tilt: Double

    static let smile = FaceExpression(leftOpen: 1, rightOpen: 1, smile: 0.78, mouthOpen: 0, tilt: 0)
    static let wink = FaceExpression(leftOpen: 0.1, rightOpen: 1, smile: 0.95, mouthOpen: 0, tilt: -7)
    static let grin = FaceExpression(leftOpen: 0.55, rightOpen: 0.55, smile: 1, mouthOpen: 0, tilt: 0)
    static let laugh = FaceExpression(leftOpen: 0.14, rightOpen: 0.14, smile: 1, mouthOpen: 1, tilt: 5)
    static let wow = FaceExpression(leftOpen: 1.22, rightOpen: 1.22, smile: 0.15, mouthOpen: 1, tilt: 0)
    static let soft = FaceExpression(leftOpen: 0.48, rightOpen: 0.48, smile: 0.46, mouthOpen: 0, tilt: 0)

    /// Shown in order, with how long to hold each one (milliseconds).
    static let script: [(FaceExpression, Int)] = [
        (.smile, 2000),
        (.wink, 640),
        (.smile, 820),
        (.grin, 1500),
        (.laugh, 1300),
        (.wow, 1100),
        (.soft, 1500)
    ]
}

/// HappyNotch's icon: a yellow face that smiles and cycles through expressions.
/// Drawn in a 100×100 design space and scaled to `size`.
struct HappyMascot: View {
    var size: CGFloat = 20
    var animates = true
    var faceColor: Color = Color(red: 1, green: 0.82, blue: 0.18)
    var featureColor: Color = Color(red: 0.16, green: 0.11, blue: 0.05)
    /// Punches the features out of the face instead of painting them (for template images).
    var featuresCutOut = false
    var resting: FaceExpression

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expression: FaceExpression

    init(
        size: CGFloat = 20,
        animates: Bool = true,
        faceColor: Color = Color(red: 1, green: 0.82, blue: 0.18),
        featureColor: Color = Color(red: 0.16, green: 0.11, blue: 0.05),
        featuresCutOut: Bool = false,
        resting: FaceExpression = .smile
    ) {
        self.size = size
        self.animates = animates
        self.faceColor = faceColor
        self.featureColor = featureColor
        self.featuresCutOut = featuresCutOut
        self.resting = resting
        _expression = State(initialValue: resting)
    }

    var body: some View {
        let s = size / 100
        ZStack {
            Circle().fill(faceColor)
            Group {
                eye(open: expression.leftOpen).offset(x: -16 * s, y: -6 * s)
                eye(open: expression.rightOpen).offset(x: 16 * s, y: -6 * s)
                mouth.offset(y: 16 * s)
            }
            .blendMode(featuresCutOut ? .destinationOut : .normal)
        }
        .compositingGroup()
        .rotationEffect(.degrees(expression.tilt))
        .frame(width: size, height: size)
        .task(id: animates && !reduceMotion) {
            guard animates, !reduceMotion else { return }
            await expressionLoop()
        }
        .accessibilityHidden(true)
    }

    private func eye(open: CGFloat) -> some View {
        let s = size / 100
        let shut = max(0, min(1, (0.22 - open) / 0.08))
        return ZStack {
            Capsule()
                .fill(featureColor)
                .frame(width: 13 * s, height: 15 * s)
                .scaleEffect(x: max(open, 0.85), y: max(open, 0.1), anchor: .center)
                .opacity(1 - shut)
            SmileArc(smile: 1)
                .stroke(featureColor, style: StrokeStyle(lineWidth: 4.2 * s, lineCap: .round))
                .frame(width: 16 * s, height: 9 * s)
                .offset(y: 3 * s)
                .opacity(shut)
        }
        .frame(width: 16 * s, height: 16 * s)
    }

    private var mouth: some View {
        let s = size / 100
        let open = expression.mouthOpen
        return ZStack {
            SmileArc(smile: expression.smile)
                .stroke(featureColor, style: StrokeStyle(lineWidth: 7 * s, lineCap: .round))
                .opacity(1 - open)
            Ellipse()
                .fill(featureColor)
                .frame(width: (16 + 18 * expression.smile) * s, height: (16 + 4 * expression.smile) * s)
                .opacity(open)
        }
        .frame(width: 46 * s, height: 28 * s)
    }

    private func expressionLoop() async {
        var index = 0
        while !Task.isCancelled {
            let (next, hold) = FaceExpression.script[index]
            withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
                expression = next
            }
            try? await Task.sleep(for: .milliseconds(hold))
            index = (index + 1) % FaceExpression.script.count
        }
    }
}

/// Upward mouth curve. `smile` runs from a small curve to a wide grin.
struct SmileArc: Shape {
    var smile: CGFloat

    var animatableData: CGFloat {
        get { smile }
        set { smile = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let smile = min(max(smile, 0), 1)
        let y = rect.minY + rect.height * (0.34 - 0.12 * smile)
        let drop = rect.height * (0.22 + 0.7 * smile)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.06, y: y))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - rect.width * 0.06, y: y),
            control: CGPoint(x: rect.midX, y: y + drop)
        )
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
            HappyMascot(size: 520, animates: false, resting: .smile)
        }
        .frame(width: 1024, height: 1024)
    }
}

extension HappyMascot {
    /// A menu bar template image of the face (black silhouette with see-through features).
    @MainActor
    static func templateImage(pointSize: CGFloat = 16) -> NSImage? {
        let renderer = ImageRenderer(
            content: HappyMascot(size: pointSize, animates: false, faceColor: .black, featureColor: .black, featuresCutOut: true)
        )
        renderer.scale = 2
        guard let cgImage = renderer.cgImage else { return nil }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: pointSize, height: pointSize))
        image.isTemplate = true
        image.accessibilityDescription = AppInfo.name
        return image
    }
}
