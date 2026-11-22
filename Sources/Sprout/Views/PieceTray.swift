import SwiftUI

/// A row's progress as a dot tray two dots deep, filled column by column.
/// Have = ink. The next dots being fetched = orange while data is moving. Missing = unlit.
struct PieceTray: View {
    let torrent: Torrent
    var grid = DotGrid(dot: 4, gap: 2)
    var rows = 2
    /// Draws in white only (have solid, missing faint), for the row to repaint in its text style.
    var selected = false
    /// The finishing sweep, 0 to 1: a band of green runs across the tray when a download completes.
    /// 1 (at rest) shows nothing extra. The row drives it from a clock only during the sweep.
    var bloom: Double = 1

    var body: some View {
        // While the torrent gives back, one column of green rings walks the tray, a step per sync.
        let tick = Int(Date.now.timeIntervalSinceReferenceDate)
        Canvas { context, size in
            let columns = grid.columns(in: size.width)
            let count = columns * rows
            let filled = Int((torrent.progress * Double(count)).rounded(.down))
            let have: Color = selected ? .white : (torrent.state.isStopped ? .secondary : .lit)
            let empty: Color = selected ? .white.opacity(0.25) : .unlit
            // The leading edge: one column of dots in flight while bytes arrive.
            let edge = torrent.isFetching ? filled..<min(count, filled + rows) : 0..<0
            let walker = !selected && torrent.isGiving && filled > 0 ? tick % max(1, filled / rows) : -1
            let front = bloom * 1.25
            for index in 0..<count {
                let column = index / rows
                let rect = grid.rect(row: index % rows, column: column)
                if index < filled {
                    let place = Double(column) / Double(columns)
                    if !selected && bloom < 1 && place <= front && place > front - 0.25 {
                        context.drawDot(rect, color: .growth)
                    } else if column == walker {
                        context.drawDot(rect, color: .growth, style: .ring)
                    } else {
                        context.drawDot(rect, color: have)
                    }
                } else if edge.contains(index) {
                    context.drawDot(rect, color: selected ? have : .signal)
                } else {
                    context.drawDot(rect, color: empty)
                }
            }
        }
        .frame(height: grid.extent(rows))
        .accessibilityHidden(true)
    }
}

/// The inspector's piece field: one dot per piece (or per group on very large torrents).
struct PieceField: View {
    /// 0 missing, 1 downloading, 2 downloaded, as reported by torrents/pieceStates.
    let states: [Int]
    var grid = DotGrid(dot: 6, gap: 2)

    @State private var width: CGFloat = 300

    var body: some View {
        let groups = PieceGroups(states: states, maxDots: 1400)
        let perRow = grid.columns(in: width)
        VStack(alignment: .leading, spacing: 10) {
            Canvas { context, size in
                let perRow = grid.columns(in: size.width)
                for (index, dot) in groups.dots.enumerated() {
                    let rect = grid.rect(row: index / perRow, column: index % perRow)
                    switch dot {
                    case .have: context.drawDot(rect, color: .lit)
                    case .partial: context.drawDot(rect, color: .lit.opacity(0.4))
                    case .inFlight: context.drawDot(rect, color: .signal)
                    case .missing: context.drawDot(rect, color: .unlit)
                    }
                }
            }
            .frame(height: grid.extent((groups.dots.count + perRow - 1) / perRow))
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }

            HStack(spacing: 14) {
                Legend(color: .lit, title: "Have")
                Legend(color: .signal, title: "In flight")
                Legend(color: .unlit, title: "Missing")
                Spacer(minLength: 0)
                if groups.piecesPerDot > 1 {
                    Text("\(groups.piecesPerDot) pieces per dot")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(states.count(where: { $0 == 2 })) of \(states.count) pieces downloaded")
    }
}

private struct Legend: View {
    let color: Color
    let title: String

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title)
        }
    }
}

private struct PieceGroups {
    enum Dot { case missing, partial, inFlight, have }

    let dots: [Dot]
    let piecesPerDot: Int

    init(states: [Int], maxDots: Int) {
        let perDot = max(1, (states.count + maxDots - 1) / maxDots)
        piecesPerDot = perDot
        dots = stride(from: 0, to: states.count, by: perDot).map { start in
            let slice = states[start..<min(start + perDot, states.count)]
            if slice.allSatisfy({ $0 == 2 }) { return .have }
            if slice.contains(1) { return .inFlight }
            if slice.contains(2) { return .partial }
            return .missing
        }
    }
}

/// Live throughput. The current download speed in large dot-matrix digits, upload in ring dots,
/// and the last minute as a scrolling dot graph: solid orange dots rise for download,
/// rings hang below the baseline for upload. Each column is one second, on a log scale.
struct PulseBand: View {
    let history: [SpeedSample]
    let current: SpeedSample

    private let graph = DotGrid(dot: 4, gap: 2)
    private let riseRows = 8
    private let hangRows = 3
    @State private var marquee: Double = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .center, spacing: 32) {
            HStack(alignment: .bottom, spacing: 26) {
                SpeedFigure(value: current.down, direction: "down", style: .solid)
                SpeedFigure(value: current.up, direction: "up", style: .ring, dot: 2.5, live: .growth)
            }
            .fixedSize()

            PulseGraph(history: history, graph: graph, riseRows: riseRows, hangRows: hangRows, marquee: marquee)
                .contentShape(Rectangle())
                // Easter egg: triple-click the graph and it spells the app's name.
                .onTapGesture(count: 3) {
                    marquee = 0
                    withAnimation(.linear(duration: reduceMotion ? 0 : 3.2)) { marquee = 1 }
                }
            .frame(height: graph.extent(riseRows + hangRows))
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .background(Color.raised)
    }

}

/// The last minute as dots, one column per second. While `marquee` runs from 0 to 1, "SPROUT"
/// scrolls through the rise rows in ink; at rest (1) it's only the graph.
private struct PulseGraph: View, Animatable {
    let history: [SpeedSample]
    let graph: DotGrid
    let riseRows: Int
    let hangRows: Int
    var marquee: Double

    nonisolated var animatableData: Double {
        get { marquee }
        set { marquee = newValue }
    }

    var body: some View {
        Canvas { context, size in
            let columns = graph.columns(in: size.width)
            let samples = Array(history.suffix(columns))
            let offset = columns - samples.count
            let peak = max(history.map { max($0.down, $0.up) }.max() ?? 0, 1)
            let word = marquee < 1 ? Self.word : []
            let wordWidth = word.first?.count ?? 0
            let shift = Int(Double(columns + wordWidth) * marquee) - wordWidth
            for column in 0..<columns {
                let sample = column >= offset ? samples[column - offset] : SpeedSample()
                let rise = level(sample.down, peak: peak, rows: riseRows)
                let hang = level(sample.up, peak: peak, rows: hangRows)
                for row in 0..<riseRows {
                    let rect = graph.rect(row: row, column: column)
                    let letter = row >= 1 && row <= DotFont.rows ? columns - 1 - column - shift : -1
                    if letter >= 0 && letter < wordWidth && word[row - 1][letter] {
                        context.drawDot(rect, color: .lit)
                    } else {
                        context.drawDot(rect, color: (riseRows - row) <= rise ? .signal : .unlit)
                    }
                }
                for row in 0..<hangRows {
                    let rect = graph.rect(row: riseRows + row, column: column)
                    if row < hang {
                        context.drawDot(rect, color: .growth, style: .ring)
                    } else {
                        context.drawDot(rect, color: .unlit.opacity(0.6))
                    }
                }
            }
        }
    }

    /// "SPROUT" as rows of lit flags, read right to left so it enters from the right edge.
    private static let word: [[Bool]] = {
        let glyphs = DotFont.glyphs(for: "SPROUT")
        return (0..<DotFont.rows).map { row in
            var line: [Bool] = []
            for (i, glyph) in glyphs.enumerated() {
                if i > 0 { line.append(false) }
                line += (0..<glyph.width).map { glyph.isLit(row: row, column: $0) }
            }
            return line.reversed()
        }
    }()

    private func level(_ value: Int64, peak: Int64, rows: Int) -> Int {
        guard value > 0 else { return 0 }
        // Log scale so 50 kB/s still shows next to 50 MB/s.
        let ratio = log10(Double(value) + 1) / log10(Double(peak) + 1)
        return max(1, Int((ratio * Double(rows)).rounded(.up)))
    }
}

/// A speed as dot-matrix digits with its unit and direction in small type underneath.
private struct SpeedFigure: View {
    let value: Int64
    let direction: String
    let style: DotStyle
    var dot: CGFloat = 4
    var live: Color = .signal

    var body: some View {
        let value = value >= Format.movingThreshold ? value : 0
        let parts = Format.speedParts(value)
        VStack(alignment: .leading, spacing: 7) {
            DotText(text: parts.number, dot: dot, color: value > 0 ? live : .secondary, style: value > 0 ? style : .solid)
            Text(value > 0 ? "\(parts.unit) \(direction)" : "idle \(direction)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(value > 0 ? "\(Format.speed(value)) \(direction)" : "Idle \(direction)")
    }
}

/// The empty state: an unlit matrix with a sprout that grows in, dot by dot from the soil up.
/// Easter egg: click it and it keeps growing, leaf by leaf, until it flowers.
struct EmptyMatrix: View {
    @State private var grown: Double = 0
    @State private var stage = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SproutMatrix(grown: grown, stage: stage)
            .contentShape(Rectangle())
            .onTapGesture {
                if stage == SproutMatrix.stages.count {
                    // Flowered: start over from a seed.
                    stage = 0
                    grown = 0
                    withAnimation(.easeOut(duration: reduceMotion ? 0 : 0.7)) { grown = 1 }
                } else {
                    withAnimation(.snappy(duration: 0.2)) { stage += 1 }
                    stage == SproutMatrix.stages.count ? Haptic.step() : Haptic.tap()
                }
            }
            .onAppear {
                withAnimation(.easeOut(duration: reduceMotion ? 0 : 0.7).delay(0.1)) { grown = 1 }
            }
            .accessibilityHidden(true)
    }
}

struct SproutMatrix: View, Animatable {
    var grown: Double
    let stage: Int

    nonisolated var animatableData: Double {
        get { grown }
        set { grown = newValue }
    }

    private static let grid = DotGrid(dot: 9, gap: 4)
    /// The sprout, 9 × 9, listed soil first so it grows upward.
    private static let sprout = [76, 67, 58, 49, 40, 39, 41, 30, 32, 29, 33]
    /// Each click adds a stage: left leaf, right leaf, a taller stem with a bud, then a flower
    /// whose petals are orange.
    static let stages: [[Int]] = [[20, 19], [24, 25], [22, 13], [4, 12, 14]]

    var body: some View {
        let lit = Set(Self.sprout.prefix(Int((grown * Double(Self.sprout.count)).rounded(.down))))
        let extra = Set(Self.stages.prefix(stage).dropLast(stage == Self.stages.count ? 1 : 0).joined())
        let petals = stage == Self.stages.count ? Set(Self.stages.last!) : []
        Canvas { context, _ in
            for index in 0..<81 {
                let rect = Self.grid.rect(row: index / 9, column: index % 9)
                let color: Color = petals.contains(index) ? .signal
                    : extra.contains(index) ? .growth
                    : lit.contains(index) ? .lit : .unlit
                context.drawDot(rect, color: color)
            }
        }
        .frame(width: Self.grid.extent(9), height: Self.grid.extent(9))
    }
}
