#if DEBUG
import SwiftUI

/// Debug only: `Sprout -SproutSnapshots <folder>` renders the dot-matrix pieces with fixture
/// torrents to PNGs, in light and dark, and quits. Lets a change be checked without the window.
@MainActor
enum Snapshots {
    static func renderIfAsked() {
        guard let folder = UserDefaults.standard.string(forKey: "SproutSnapshots") else { return }
        NSApp.setActivationPolicy(.prohibited)
        let out = URL(fileURLWithPath: folder)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        for scheme in [ColorScheme.light, .dark] {
            let name = scheme == .dark ? "dark" : "light"
            save(rows.environment(\.colorScheme, scheme), out.appending(path: "rows-\(name).png"))
            save(pulse.environment(\.colorScheme, scheme), out.appending(path: "pulse-\(name).png"))
        }
        save(dock, out.appending(path: "dock.png"))
        exit(0)
    }

    private static func torrent(_ name: String, _ state: String, _ progress: Double, down: Int = 0, up: Int = 0, ratio: Double = 0) -> Torrent {
        Torrent(hash: name, fields: [
            "name": .string(name), "state": .string(state), "progress": .number(progress),
            "dlspeed": .number(Double(down)), "upspeed": .number(Double(up)), "size": .number(4_200_000_000),
            "ratio": .number(ratio), "eta": .number(down > 0 ? 1800 : 8_640_000),
        ])
    }

    private static var rows: some View {
        VStack(spacing: 0) {
            SeedBed(torrent: torrent("Downloading.iso", "downloading", 0.42, down: 4_200_000, up: 80_000))
            SeedBed(torrent: torrent("Seeding.mkv", "uploading", 1, up: 820_000, ratio: 1.4))
            SeedBed(torrent: torrent("Seeding idle", "stalledUP", 1, ratio: 0.3))
            SeedBed(torrent: torrent("Waiting for peers", "stalledDL", 0.1))
            SeedBed(torrent: torrent("Checking", "checkingDL", 0.6))
            SeedBed(torrent: torrent("Stopped", "stoppedDL", 0.3))
            SeedBed(torrent: torrent("Broken", "error", 0.5))
            SeedBed(torrent: torrent("Bloom midway", "uploading", 1), bloomPreview: 0.5, donePreview: true)
            HStack(spacing: 20) { ForEach(0..<5) { SproutMatrix(grown: $0 == 0 ? 0.5 : 1, stage: $0 - ($0 > 0 ? 0 : 0)).scaleEffect(0.6) }; StatusLabel(state: .uploading); StatusLabel(state: .queuedDL) }.padding()
        }
        .frame(width: 640)
        .padding()
        .background(Color.ground)
    }

    private static var pulse: some View {
        PulseBand(history: (0..<90).map { SpeedSample(down: Int64(abs(sin(Double($0) / 6)) * 5_000_000), up: Int64($0 % 7) * 90_000) },
                  current: SpeedSample(down: 4_200_000, up: 820_000))
            .frame(width: 640)
    }

    private static var dock: some View {
        HStack {
            DockSprout(grown: 6, tip: .signal, blooming: false)
            DockSprout(grown: 30, tip: .growth, blooming: false)
            DockSprout(grown: DockSprout.order.count, tip: nil, blooming: true)
        }
        .frame(width: 128 * 3, height: 128)
        .background(Color.gray)
    }

    private static func save(_ view: some View, _ url: URL) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.cgImage else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
