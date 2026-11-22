import SwiftUI

/// The Dock icon comes alive while Sprout downloads. The icon's seedling grows with the overall
/// download progress, dot by dot from the soil up, its tip dot orange while bytes come in.
/// A finished download flowers the plant green for a moment. Otherwise, seeding included, the
/// Dock shows the normal app icon, so the glass icon isn't swapped out most of the day.
@MainActor
enum DockTile {
    private static var shown: DockSprout?
    private static let imageView = NSImageView()

    static func update(torrents: some Collection<Torrent>, finishedAt: [String: Date]) {
        let fetching = torrents.contains(where: \.isFetching)
        let blooming = finishedAt.values.contains { $0.timeIntervalSinceNow > -2 }
        guard fetching || blooming else { return show(nil) }

        // Progress across everything still downloading, weighted by size.
        let open = torrents.filter { $0.progress < 1 && !$0.state.isStopped && $0.size > 0 }
        let total = open.reduce(0.0) { $0 + Double($1.size) }
        let done = open.reduce(0.0) { $0 + Double($1.size) * $1.progress }
        let progress = total > 0 ? done / total : 1
        let grown = Int((progress * Double(DockSprout.order.count)).rounded(.down))
        show(DockSprout(grown: grown, tip: fetching ? .signal : nil, blooming: blooming))
    }

    private static func show(_ sprout: DockSprout?) {
        // The Dock redraws only when the picture changes: at most a handful of dots per second.
        guard sprout != shown else { return }
        shown = sprout
        let tile = NSApp.dockTile
        // Drawn to an image first: a live SwiftUI view hadn't redrawn yet when the Dock took its
        // snapshot, so the tile lagged a frame behind and stuck on the last one.
        if let sprout {
            let renderer = ImageRenderer(content: sprout.frame(width: tile.size.width, height: tile.size.height))
            renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
            imageView.image = renderer.nsImage
            imageView.frame = NSRect(origin: .zero, size: tile.size)
            if tile.contentView !== imageView { tile.contentView = imageView }
        } else {
            tile.contentView = nil
        }
        tile.display()
    }
}

/// The app icon's seedling (scripts/make-icon.py), drawn live.
struct DockSprout: View, Equatable {
    let grown: Int
    let tip: Color?
    let blooming: Bool

    static let pattern = [
        ".............",
        ".##.......#o.",
        "####.....####",
        "#####...#####",
        ".#####.#####.",
        "...###.###...",
        ".....###.....",
        "......#......",
        "......#......",
        "......#......",
        "......#......",
        ".###########.",
        ".............",
    ].map(Array.init)

    /// Soil row index: always lit, it's the bed the plant grows from.
    private static let soil = 11

    /// Plant dots in growing order: bottom row first, and from the stem outwards within a row.
    static let order: [Int] = {
        var dots: [(row: Int, column: Int)] = []
        for (row, line) in pattern.enumerated() where row != soil {
            for (column, c) in line.enumerated() where c == "#" { dots.append((row, column)) }
        }
        return dots.sorted { $0.row != $1.row ? $0.row > $1.row : abs($0.column - 6) < abs($1.column - 6) }
            .map { $0.row * 13 + $0.column }
    }()

    var body: some View {
        GeometryReader { proxy in
            // Same footprint as a macOS app icon: the panel fills about 80 % of the tile.
            let side = proxy.size.width * 0.8
            let pitch = side / 15.2
            let dot = pitch * 0.74
            let lit = Set(Self.order.prefix(grown))
            ZStack {
                RoundedRectangle(cornerRadius: side * 0.225, style: .continuous)
                    .fill(.black)
                    .overlay {
                        RoundedRectangle(cornerRadius: side * 0.225, style: .continuous)
                            .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.35), radius: side * 0.02, y: side * 0.015)
                Canvas { context, size in
                    let origin = (size.width - pitch * 12) / 2
                    for (row, line) in Self.pattern.enumerated() {
                        for (column, c) in line.enumerated() {
                            let rect = CGRect(x: origin + CGFloat(column) * pitch - dot / 2,
                                              y: origin + CGFloat(row) * pitch - dot / 2, width: dot, height: dot)
                            let index = row * 13 + column
                            let color: Color = switch c {
                            case "o": tip ?? .white.opacity(0.10)
                            case "#" where row == Self.soil: .white
                            case "#" where lit.contains(index): blooming ? Color(red: 0.24, green: 0.86, blue: 0.42) : .white
                            default: .white.opacity(0.10)
                            }
                            context.fill(Path(ellipseIn: rect), with: .color(color))
                        }
                    }
                }
                .frame(width: side, height: side)
            }
            .frame(width: side, height: side)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        // The Dock is always drawn dark-on-anything; the panel is black like the icon.
        .environment(\.colorScheme, .dark)
    }

    nonisolated static func == (a: Self, b: Self) -> Bool {
        a.grown == b.grown && a.tip == b.tip && a.blooming == b.blooming
    }
}
