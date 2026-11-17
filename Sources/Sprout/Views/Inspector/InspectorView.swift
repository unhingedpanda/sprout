import SwiftUI

struct InspectorView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("inspectorTab") private var tab: Tab = .general

    enum Tab: String, CaseIterable, Identifiable {
        case general, files, peers, trackers
        var id: Self { self }
        var title: String { rawValue.capitalized }
    }

    var body: some View {
        let selected = model.selectedTorrents
        if selected.count == 1, let torrent = selected.first, let api = model.engine.api {
            VStack(spacing: 0) {
                Picker("Inspector section", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                switch tab {
                case .general: GeneralPane(torrent: torrent, api: api)
                case .files: FilesPane(torrent: torrent, api: api)
                case .peers: PeersPane(torrent: torrent, api: api)
                case .trackers: TrackersPane(torrent: torrent, api: api)
                }
            }
            .id(torrent.id)
        } else if selected.isEmpty {
            ContentUnavailableView("No torrent selected", systemImage: "sidebar.trailing",
                                   description: Text("Select a torrent to see its files, peers and trackers."))
        } else {
            ContentUnavailableView("\(selected.count) torrents selected", systemImage: "square.stack",
                                   description: Text("Select one torrent to inspect it."))
        }
    }
}

extension InspectorView {
    /// The inspector sits on the same loam ground as the window.
    func groundedInspector() -> some View {
        self.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.ground)
    }
}

/// Re-runs `load` every two seconds while the pane is visible.
private struct Polling: ViewModifier {
    let id: String
    let load: () async -> Void

    func body(content: Content) -> some View {
        content.task(id: id) {
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}

extension View {
    func polling(id: String, _ load: @escaping () async -> Void) -> some View {
        modifier(Polling(id: id, load: load))
    }
}

// MARK: General

private struct GeneralPane: View {
    let torrent: Torrent
    let api: WebAPI

    @State private var properties: [String: JSON] = [:]
    @State private var pieces: [Int] = []

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    Text(torrent.name)
                        .font(.headline)
                        .lineLimit(3)
                    HStack(alignment: .bottom) {
                        DotText(text: Format.percentDigits(torrent.progress), dot: 6, color: torrent.figureColor)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            StatusLabel(state: torrent.state)
                            if torrent.hasKnownETA {
                                Text("\(Format.eta(torrent)) left").foregroundStyle(.secondary)
                            }
                        }
                        .font(.callout)
                    }
                    if pieces.isEmpty {
                        PieceTray(torrent: torrent, grid: DotGrid(dot: 6, gap: 2))
                    } else {
                        PieceField(states: pieces)
                    }
                }
                .padding(.vertical, 6)
            }

            Section("Transfer") {
                LabeledContent("Downloaded", value: Format.bytes(properties.int("total_downloaded")))
                LabeledContent("Uploaded", value: Format.bytes(properties.int("total_uploaded")))
                LabeledContent("Ratio", value: Format.ratio(torrent.ratio))
                LabeledContent("Seeds", value: swarm("seeds"))
                LabeledContent("Peers", value: swarm("peers"))
                LabeledContent("Active for", value: Format.duration(seconds: properties.int("time_elapsed")))
                LabeledContent("Wasted", value: Format.bytes(properties.int("total_wasted")))
            }

            Section("Torrent") {
                LabeledContent("Size", value: Format.bytes(properties.int("total_size")))
                LabeledContent("Pieces", value: piecesSummary)
                LabeledContent("Added", value: Format.date(torrent.addedOn))
                LabeledContent("Completed", value: Format.date(date("completion_date")))
                LabeledContent("Saved in") {
                    Button(URL(filePath: torrent.savePath).lastPathComponent) {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: torrent.savePath)])
                    }
                    .buttonStyle(.link)
                    .help(torrent.savePath)
                }
                if !properties.string("created_by").isEmpty {
                    LabeledContent("Created by", value: properties.string("created_by"))
                }
                if !properties.string("comment").isEmpty {
                    LabeledContent("Comment") {
                        Text(properties.string("comment")).textSelection(.enabled)
                    }
                }
                LabeledContent("Info hash") {
                    Text(torrent.id).font(.caption.monospaced()).textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .monospacedDigit()
        .polling(id: torrent.id) {
            async let props = try? api.properties(hash: torrent.id)
            async let states = try? api.pieceStates(hash: torrent.id)
            if let fields = await props?.object { properties = fields }
            if let states = await states { pieces = states }
        }
    }

    /// Connected count, plus the swarm size the trackers report when they report one.
    private func swarm(_ key: String) -> String {
        let connected = properties.int(key)
        let total = properties.int("\(key)_total")
        return total > 0 ? "\(connected) connected, \(total) in swarm" : "\(connected) connected"
    }

    private var piecesSummary: String {
        let count = properties.int("pieces_num")
        guard count > 0 else { return "Unknown" }
        return "\(count.formatted()) × \(Format.bytes(properties.int("piece_size")))"
    }

    private func date(_ key: String) -> Date? {
        let seconds = properties.double(key)
        return seconds > 0 ? Date(timeIntervalSince1970: seconds) : nil
    }
}

// MARK: Files

private struct FilesPane: View {
    let torrent: Torrent
    let api: WebAPI

    @State private var files: [TorrentFile] = []
    @State private var error: String?

    var body: some View {
        List(files) { file in
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Toggle("Download \(URL(filePath: file.name).lastPathComponent)", isOn: Binding(
                    get: { file.priority != .skip },
                    set: { setPriority($0 ? .normal : .skip, for: file) }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .help(file.priority == .skip ? "Download this file" : "Skip this file")

                VStack(alignment: .leading, spacing: 2) {
                    Text(URL(filePath: file.name).lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(file.name)
                    Text("\(Format.bytes(file.size)), \(Format.percent(file.progress))")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if file.priority == .high || file.priority == .maximum {
                    Text(file.priority.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .opacity(file.priority == .skip ? 0.55 : 1)
            .contextMenu {
                Picker("Priority", selection: Binding(get: { file.priority }, set: { setPriority($0, for: file) })) {
                    ForEach(FilePriority.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
            }
        }
        .scrollContentBackground(.hidden)
        .overlay {
            if files.isEmpty {
                ContentUnavailableView("No file list yet", systemImage: "doc",
                                       description: Text("Files appear once the torrent's metadata arrives."))
            }
        }
        .polling(id: torrent.id) {
            if let loaded = try? await api.files(hash: torrent.id) { files = loaded }
        }
    }

    private func setPriority(_ priority: FilePriority, for file: TorrentFile) {
        Task {
            try? await api.setFilePriority(hash: torrent.id, fileIndexes: [file.id], priority: priority)
            if let loaded = try? await api.files(hash: torrent.id) { files = loaded }
        }
    }
}

// MARK: Peers

private struct PeersPane: View {
    let torrent: Torrent
    let api: WebAPI

    @State private var peers: [Peer] = []

    var body: some View {
        List(peers) { peer in
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(peer.client.isEmpty ? "Unknown client" : peer.client).lineLimit(1)
                    Text(peer.countryCode.isEmpty ? peer.id : "\(peer.id), \(peer.countryCode)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 8) {
                        if peer.downloadSpeed > 0 {
                            Text(Format.speed(peer.downloadSpeed)).foregroundStyle(Color.signal)
                        }
                        if peer.uploadSpeed > 0 {
                            Text(Format.speed(peer.uploadSpeed)).foregroundStyle(Color.signal)
                        }
                    }
                    Text("has \(Format.percent(peer.progress))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .monospacedDigit()
            }
        }
        .scrollContentBackground(.hidden)
        .overlay {
            if peers.isEmpty {
                ContentUnavailableView("No connected peers", systemImage: "person.2",
                                       description: Text("Peers show up here while the torrent is connected to the swarm."))
            }
        }
        .polling(id: torrent.id) {
            if let loaded = try? await api.peers(hash: torrent.id) {
                peers = loaded.sorted { ($0.downloadSpeed + $0.uploadSpeed) > ($1.downloadSpeed + $1.uploadSpeed) }
            }
        }
    }
}

// MARK: Trackers

private struct TrackersPane: View {
    let torrent: Torrent
    let api: WebAPI

    @State private var trackers: [Tracker] = []

    var body: some View {
        List(trackers) { tracker in
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(tracker.displayName).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text(tracker.statusLabel)
                        .font(.caption)
                        .foregroundStyle(tracker.isFailing ? AnyShapeStyle(Color.fault) : AnyShapeStyle(.secondary))
                }
                // The engine reports -1 when a tracker hasn't given counts.
                if !tracker.isPseudoTracker && tracker.seeds >= 0 && tracker.peers >= 0 {
                    Text("\(tracker.seeds.formatted()) seeds, \(tracker.peers.formatted()) peers")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                if !tracker.message.isEmpty {
                    Text(tracker.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .help(tracker.url)
        }
        .scrollContentBackground(.hidden)
        .polling(id: torrent.id) {
            if let loaded = try? await api.trackers(hash: torrent.id) { trackers = loaded }
        }
    }
}
