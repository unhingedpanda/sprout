import SwiftUI

/// A row's progress as a dot tray two dots deep, filled column by column.
/// Have = ink. The next dots being fetched = orange while data is moving. Missing = unlit.
struct PieceTray: View {
    let torrent: Torrent
    var grid = DotGrid(dot: 4, gap: 2)
    var rows = 2
    /// Draws in white only (have solid, missing faint), for the row to repaint in its text style.
    var selected = false

    var body: some View {
        Canvas { context, size in
            let count = grid.columns(in: size.width) * rows
            let filled = Int((torrent.progress * Double(count)).rounded(.down))
            let have: Color = selected ? .white : (torrent.state.isStopped ? .secondary : .lit)
            let empty: Color = selected ? .white.opacity(0.25) : .unlit
            // The leading edge: one column of dots in flight while bytes arrive.
            let edge = torrent.downloadSpeed >= Format.movingThreshold && torrent.progress < 1 ? filled..<min(count, filled + rows) : 0..<0
            for index in 0..<count {
                let rect = grid.rect(row: index % rows, column: index / rows)
                if index < filled {
                    context.drawDot(rect, color: have)
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

    var body: some View {
        HStack(alignment: .center, spacing: 32) {
            HStack(alignment: .bottom, spacing: 26) {
                SpeedFigure(value: current.down, direction: "down", style: .solid)
                SpeedFigure(value: current.up, direction: "up", style: .ring, dot: 2.5)
            }
            .fixedSize()

            Canvas { context, size in
                let columns = graph.columns(in: size.width)
                let samples = Array(history.suffix(columns))
                let offset = columns - samples.count
                let peak = max(history.map { max($0.down, $0.up) }.max() ?? 0, 1)
                for column in 0..<columns {
                    let sample = column >= offset ? samples[column - offset] : SpeedSample()
                    let rise = level(sample.down, peak: peak, rows: riseRows)
                    let hang = level(sample.up, peak: peak, rows: hangRows)
                    for row in 0..<riseRows {
                        let on = (riseRows - row) <= rise
                        context.drawDot(graph.rect(row: row, column: column), color: on ? .signal : .unlit)
                    }
                    for row in 0..<hangRows {
                        let rect = graph.rect(row: riseRows + row, column: column)
                        if row < hang {
                            context.drawDot(rect, color: .signal, style: .ring)
                        } else {
                            context.drawDot(rect, color: .unlit.opacity(0.6))
                        }
                    }
                }
            }
            .frame(height: graph.extent(riseRows + hangRows))
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .background(Color.raised)
    }

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

    var body: some View {
        let value = value >= Format.movingThreshold ? value : 0
        let parts = Format.speedParts(value)
        VStack(alignment: .leading, spacing: 7) {
            DotText(text: parts.number, dot: dot, color: value > 0 ? .signal : .secondary, style: value > 0 ? style : .solid)
            Text(value > 0 ? "\(parts.unit) \(direction)" : "idle \(direction)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(value > 0 ? "\(Format.speed(value)) \(direction)" : "Idle \(direction)")
    }
}

/// The empty state: an unlit matrix with a single sprout lit in it.
struct EmptyMatrix: View {
    private let grid = DotGrid(dot: 9, gap: 4)
    // A small sprout, 9 columns × 9 rows.
    private let sprout: Set<Int> = [22, 23, 29, 30, 31, 32, 40, 49, 58, 67, 76]

    var body: some View {
        Canvas { context, _ in
            for index in 0..<81 {
                let rect = grid.rect(row: index / 9, column: index % 9)
                context.drawDot(rect, color: sprout.contains(index) ? .lit : .unlit)
            }
        }
        .frame(width: grid.extent(9), height: grid.extent(9))
        .accessibilityHidden(true)
    }
}
