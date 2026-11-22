import SwiftUI

/// Speed and seeding limits for one or more torrents, on top of the limits in Settings.
struct LimitsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let hashes: Set<String>

    enum Seeding: Hashable { case settings, unlimited, custom }

    @State private var download = 0.0
    @State private var upload = 0.0
    @State private var seeding = Seeding.settings
    @State private var useRatio = false
    @State private var ratio = 2.0
    @State private var useTime = false
    @State private var hours = 24.0
    @State private var useIdle = false
    @State private var idleMinutes = 60.0
    @State private var action = -1

    private var title: String {
        if hashes.count == 1, let name = hashes.first.flatMap({ model.torrents[$0]?.name }) { return name }
        return "\(hashes.count) torrents"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: "Speed and Seeding Limits", subtitle: title)
            Form {
                Section {
                    UnitField(title: "Download", value: $download, unit: "KB/s")
                    UnitField(title: "Upload", value: $upload, unit: "KB/s")
                } header: {
                    Text("Speed")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if differs {
                            Text("These torrents have different limits. The form shows \(firstName)’s. Only what you change is applied to all of them.")
                        }
                        Text("0 means no limit of its own. The limits in Settings still apply.")
                    }
                }

                Section {
                    Picker("Stop seeding", selection: $seeding) {
                        Text("As set in Settings").tag(Seeding.settings)
                        Text("Never").tag(Seeding.unlimited)
                        Text("At these limits").tag(Seeding.custom)
                    }
                    if seeding == .custom {
                        Toggle("At a share ratio", isOn: $useRatio)
                        if useRatio { UnitField(title: "Ratio", value: $ratio, unit: "× size", fraction: true) }
                        Toggle("After a seeding time", isOn: $useTime)
                        if useTime { UnitField(title: "Time", value: $hours, unit: "hours", fraction: true) }
                        Toggle("After a time without uploads", isOn: $useIdle)
                        if useIdle { UnitField(title: "Idle", value: $idleMinutes, unit: "minutes") }
                        Picker("Then", selection: $action) {
                            Text("Do what Settings says").tag(-1)
                            Text("Stop the torrent").tag(0)
                            Text("Remove the torrent").tag(1)
                            Text("Remove the torrent and its files").tag(3)
                            Text("Switch to super seeding").tag(2)
                        }
                    }
                } header: {
                    Text("Seeding")
                } footer: {
                    if seeding == .custom && !useRatio && !useTime && !useIdle {
                        Text("With no limit turned on, the torrent seeds until you stop it.")
                    }
                }
            }
            .sheetForm()
        }
        .sproutSheet(width: 460)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel", role: .cancel) { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Apply") { apply() }.tint(.action) }
        }
        .onAppear(perform: load)
    }

    /// What the sheet opened with, so Apply only sends what was changed.
    @State private var initial: Snapshot?

    private struct Snapshot: Equatable {
        var download: Double
        var upload: Double
        var share: ShareLimits
    }

    /// Starts from the first torrent by name. Apply only sends the limits the user changed,
    /// so each torrent keeps its own value for everything else.
    private func load() {
        let torrents = hashes.compactMap { model.torrents[$0] }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        guard let torrent = torrents.first else { return }
        firstName = torrent.name
        differs = torrents.contains {
            $0.downloadLimit != torrent.downloadLimit || $0.uploadLimit != torrent.uploadLimit || $0.shareLimits != torrent.shareLimits
        }
        download = Double(torrent.downloadLimit) / 1024
        upload = Double(torrent.uploadLimit) / 1024
        let limits = torrent.shareLimits
        seeding = limits.followsSettings ? .settings : limits.isUnlimited ? .unlimited : .custom
        useRatio = limits.ratio >= 0
        if useRatio { ratio = limits.ratio }
        useTime = limits.seedingTime >= 0
        if useTime { hours = limits.seedingTime / 60 }
        useIdle = limits.inactiveTime >= 0
        if useIdle { idleMinutes = limits.inactiveTime }
        action = limits.action
        mode = limits.mode
        initial = Snapshot(download: download, upload: upload, share: share)
    }

    @State private var mode = "Default"
    @State private var differs = false
    @State private var firstName = ""

    /// The seeding limits as the form now reads.
    private var share: ShareLimits {
        var limits: ShareLimits = switch seeding {
        case .settings: ShareLimits()
        case .unlimited: ShareLimits(ratio: ShareLimits.none, seedingTime: ShareLimits.none, inactiveTime: ShareLimits.none)
        case .custom: ShareLimits(
            // The engine caps ratio at 9998 and keeps times as 32-bit minutes.
            ratio: useRatio ? min(max(0, ratio), 9998) : ShareLimits.none,
            seedingTime: useTime ? min(max(0, (hours * 60).rounded()), 1_000_000_000) : ShareLimits.none,
            inactiveTime: useIdle ? min(max(0, idleMinutes.rounded()), 1_000_000_000) : ShareLimits.none,
            action: action
        )
        }
        limits.mode = mode
        return limits
    }

    private func apply() {
        // Commit a number still being typed, so Return applies what's on screen.
        NSApp.keyWindow?.makeFirstResponder(nil)
        DispatchQueue.main.async {
            let now = Snapshot(download: download, upload: upload, share: share)
            let before = initial
            model.setLimits(
                on: hashes,
                download: now.download == before?.download ? nil : Self.bytes(now.download),
                upload: now.upload == before?.upload ? nil : Self.bytes(now.upload),
                share: now.share == before?.share ? nil : now.share
            )
            dismiss()
        }
    }

    /// KB/s to bytes per second, capped so a huge number can't overflow. The engine rounds to whole KiB.
    private static func bytes(_ kilobytes: Double) -> Int64 {
        Int64(min(max(0, kilobytes), 2_000_000) * 1024)
    }
}
