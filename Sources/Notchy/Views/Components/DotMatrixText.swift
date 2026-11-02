import SwiftUI

/// Renders digits as a 5×7 dot-matrix display, with unlit dots drawn faintly.
struct DotMatrixText: View {
    let text: String
    var dot: CGFloat = 3.4
    var spacing: CGFloat = 1.6
    var color: Color = DS.ink

    private var glyphs: [DotFont.Glyph] { text.compactMap { DotFont.glyphs[$0] } }

    var body: some View {
        let pitch = dot + spacing
        let glyphs = self.glyphs
        let columns = glyphs.reduce(0) { $0 + $1.width } + max(0, glyphs.count - 1)
        Canvas { context, _ in
            var x: CGFloat = 0
            for glyph in glyphs {
                for (row, bits) in glyph.rows.enumerated() {
                    for column in 0..<glyph.width {
                        let rect = CGRect(x: x + CGFloat(column) * pitch, y: CGFloat(row) * pitch, width: dot, height: dot)
                        context.fill(Path(ellipseIn: rect), with: .color(bits[column] ? color : color.opacity(0.08)))
                    }
                }
                x += CGFloat(glyph.width + 1) * pitch
            }
        }
        .frame(width: max(0, CGFloat(columns) * pitch - spacing), height: 7 * pitch - spacing)
        .accessibilityHidden(true)
    }
}

enum DotFont {
    struct Glyph {
        let width: Int
        let rows: [[Bool]]
    }

    private static let raw: [Character: [String]] = [
        "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
        "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
        "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
        "3": ["11111", "00010", "00100", "00010", "00001", "10001", "01110"],
        "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
        "5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
        "6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
        "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
        "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
        "9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
        ":": ["0", "0", "1", "0", "1", "0", "0"],
    ]

    static let glyphs: [Character: Glyph] = raw.mapValues { rows in
        Glyph(width: rows[0].count, rows: rows.map { $0.map { $0 == "1" } })
    }
}
