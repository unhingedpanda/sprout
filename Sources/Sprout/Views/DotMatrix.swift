import SwiftUI

/// The one dot grid every view draws from.
struct DotGrid {
    let dot: CGFloat
    var gap: CGFloat

    init(dot: CGFloat, gap: CGFloat? = nil) {
        self.dot = dot
        self.gap = gap ?? max(1, (dot * 0.4).rounded())
    }

    var pitch: CGFloat { dot + gap }

    func columns(in width: CGFloat) -> Int { max(1, Int((width + gap) / pitch)) }

    func rect(row: Int, column: Int) -> CGRect {
        CGRect(x: CGFloat(column) * pitch, y: CGFloat(row) * pitch, width: dot, height: dot)
    }

    func extent(_ count: Int) -> CGFloat { max(dot, CGFloat(count) * pitch - gap) }
}

enum DotStyle {
    /// Download, have, plain figures.
    case solid
    /// Upload.
    case ring
}

extension GraphicsContext {
    func drawDot(_ rect: CGRect, color: Color, style: DotStyle = .solid) {
        switch style {
        case .solid:
            fill(Path(ellipseIn: rect), with: .color(color))
        case .ring:
            let width = max(1, rect.width * 0.28)
            stroke(Path(ellipseIn: rect.insetBy(dx: width / 2, dy: width / 2)), with: .color(color), lineWidth: width)
        }
    }
}

/// A 5×7 dot-matrix font. Each glyph is seven rows of bits, most significant bit on the left.
enum DotFont {
    static let rows = 7

    struct Glyph {
        let width: Int
        let bits: [UInt8]

        func isLit(row: Int, column: Int) -> Bool {
            bits[row] >> UInt8(width - 1 - column) & 1 == 1
        }
    }

    private static func glyph(_ rows: [String]) -> Glyph {
        Glyph(width: rows[0].count, bits: rows.map { UInt8($0, radix: 2)! })
    }

    static let glyphs: [Character: Glyph] = [
        "0": glyph(["01110", "10001", "10011", "10101", "11001", "10001", "01110"]),
        "1": glyph(["00100", "01100", "00100", "00100", "00100", "00100", "01110"]),
        "2": glyph(["01110", "10001", "00001", "00010", "00100", "01000", "11111"]),
        "3": glyph(["11111", "00010", "00100", "00010", "00001", "10001", "01110"]),
        "4": glyph(["00010", "00110", "01010", "10010", "11111", "00010", "00010"]),
        "5": glyph(["11111", "10000", "11110", "00001", "00001", "10001", "01110"]),
        "6": glyph(["00110", "01000", "10000", "11110", "10001", "10001", "01110"]),
        "7": glyph(["11111", "00001", "00010", "00100", "01000", "01000", "01000"]),
        "8": glyph(["01110", "10001", "10001", "01110", "10001", "10001", "01110"]),
        "9": glyph(["01110", "10001", "10001", "01111", "00001", "00010", "01100"]),
        ".": glyph(["0", "0", "0", "0", "0", "0", "1"]),
        "%": glyph(["11001", "11010", "00010", "00100", "01000", "01011", "10011"]),
        "-": glyph(["000", "000", "000", "111", "000", "000", "000"]),
        " ": glyph(["00", "00", "00", "00", "00", "00", "00"]),
        "D": glyph(["11110", "10001", "10001", "10001", "10001", "10001", "11110"]),
        "O": glyph(["01110", "10001", "10001", "10001", "10001", "10001", "01110"]),
        "N": glyph(["10001", "11001", "10101", "10011", "10001", "10001", "10001"]),
        "E": glyph(["11111", "10000", "10000", "11110", "10000", "10000", "11111"]),
        "I": glyph(["111", "010", "010", "010", "010", "010", "111"]),
        "L": glyph(["10000", "10000", "10000", "10000", "10000", "10000", "11111"]),
        "S": glyph(["01111", "10000", "10000", "01110", "00001", "00001", "11110"]),
        "P": glyph(["11110", "10001", "10001", "11110", "10000", "10000", "10000"]),
        "R": glyph(["11110", "10001", "10001", "11110", "10100", "10010", "10001"]),
        "U": glyph(["10001", "10001", "10001", "10001", "10001", "10001", "01110"]),
        "T": glyph(["11111", "00100", "00100", "00100", "00100", "00100", "00100"]),
    ]

    static func glyphs(for text: String) -> [Glyph] {
        text.uppercased().compactMap { glyphs[$0] }
    }

    /// Width in dot columns, with one empty column between glyphs.
    static func columns(for text: String) -> Int {
        let list = glyphs(for: text)
        return list.reduce(0) { $0 + $1.width } + max(0, list.count - 1)
    }
}

/// Text drawn as dot-matrix glyphs on the shared grid. Unlit dots inside each glyph stay faintly
/// visible, like an LED panel, so the number reads as part of the same matrix as the data.
struct DotText: View {
    let text: String
    var dot: CGFloat = 3
    var color: Color = .lit
    var style: DotStyle = .solid
    var showsUnlit = true

    var body: some View {
        let grid = DotGrid(dot: dot)
        let columns = DotFont.columns(for: text)
        Canvas { context, _ in
            var x = 0
            for glyph in DotFont.glyphs(for: text) {
                for row in 0..<DotFont.rows {
                    for column in 0..<glyph.width {
                        let rect = grid.rect(row: row, column: x + column)
                        if glyph.isLit(row: row, column: column) {
                            context.drawDot(rect, color: color, style: style)
                        } else if showsUnlit {
                            context.drawDot(rect, color: .unlit)
                        }
                    }
                }
                x += glyph.width + 1
            }
        }
        .frame(width: grid.extent(columns), height: grid.extent(DotFont.rows))
        .accessibilityElement()
        .accessibilityLabel(text)
    }
}
