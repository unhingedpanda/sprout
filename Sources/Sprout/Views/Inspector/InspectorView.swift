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
    @Environment(AppModel.self) private var model
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

            Section {
                LabeledContent("Download", value: limit(torrent.downloadLimit))
                LabeledContent("Upload", value: limit(torrent.uploadLimit))
                LabeledContent("Seeding", value: torrent.shareLimits.summary)
            } header: {
                HStack {
                    Text("Limits")
                    Spacer()
                    Button("Change…") { model.pendingLimits = [torrent.id] }
                        .buttonStyle(.link)
                        .font(.callout)
                }
            }

            Section("Torrent") {
                LabeledContent("Size", value: properties.int("total_size") < 0 ? "Unknown" : Format.bytes(properties.int("total_size")))
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
                if torrent.infoHashV1.isEmpty && torrent.infoHashV2.isEmpty {
                    LabeledContent("Info hash") {
                        Text(torrent.id).font(.caption.monospaced()).textSelection(.enabled)
                    }
                }
                if !torrent.infoHashV1.isEmpty {
                    LabeledContent(torrent.infoHashV2.isEmpty ? "Info hash" : "Info hash v1") {
                        Text(torrent.infoHashV1).font(.caption.monospaced()).textSelection(.enabled)
                    }
                }
                if !torrent.infoHashV2.isEmpty {
                    LabeledContent(torrent.infoHashV1.isEmpty ? "Info hash" : "Info hash v2") {
                        Text(torrent.infoHashV2).font(.caption.monospaced()).textSelection(.enabled)
                    }
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

    private func limit(_ bytes: Int64) -> String {
        bytes > 0 ? "\((Double(bytes) / 1024).formatted(.number.precision(.fractionLength(0...1)))) KB/s" : "No limit"
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

    @Environment(AppModel.self) private var model
    @State private var files: [TorrentFile] = []
    @State private var renaming: Rename?
    @State private var newName = ""

    struct Rename: Equatable {
        let oldPath: String
        let isFolder: Bool
    }

    /// The folder holding this file inside the torrent, if it's in one.
    private func folder(of file: TorrentFile) -> String? {
        let parts = file.name.split(separator: "/")
        return parts.count > 1 ? parts.dropLast().joined(separator: "/") : nil
    }

    private func apply(_ rename: Rename) {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        renaming = nil
        guard !name.isEmpty, !name.contains("/") else { return }
        // Paths inside a torrent are relative and always use "/".
        let parent = rename.oldPath.split(separator: "/").dropLast().joined(separator: "/")
        let newPath = parent.isEmpty ? name : "\(parent)/\(name)"
        guard newPath != rename.oldPath else { return }
        let hash = torrent.id
        model.run { api in
            try await api.call(rename.isFolder ? "torrents/renameFolder" : "torrents/renameFile",
                               ["hash": hash, "oldPath": rename.oldPath, "newPath": newPath])
        }
    }

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
                    Text(folder(of: file).map { "\(Format.bytes(file.size)), \(Format.percent(file.progress)), in \($0)" }
                         ?? "\(Format.bytes(file.size)), \(Format.percent(file.progress))")
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
                Divider()
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: torrent.savePath).appending(path: file.name)])
                }
                .disabled(file.progress <= 0)
                Button("Rename…") { renaming = Rename(oldPath: file.name, isFolder: false) }
                if let folder = folder(of: file) {
                    Button("Rename Folder “\(URL(filePath: folder).lastPathComponent)”…") {
                        renaming = Rename(oldPath: folder, isFolder: true)
                    }
                }
            }
        }
        .alert(renaming?.isFolder == true ? "Rename Folder" : "Rename File",
               isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }),
               presenting: renaming) { rename in
            TextField("Name", text: $newName)
            Button("Rename") { apply(rename) }
            Button("Cancel", role: .cancel) {}
        } message: { rename in
            Text(rename.isFolder ? "Every file inside moves with it." : "The file on disk is renamed too.")
        }
        .onChange(of: renaming?.oldPath) { newName = renaming.map { URL(filePath: $0.oldPath).lastPathComponent } ?? "" }
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
    @Environment(AppModel.self) private var model
    let torrent: Torrent
    let api: WebAPI

    @State private var peers: [Peer] = []
    @State private var addingPeers = false
    @State private var banning: Peer?

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
            .contextMenu {
                Button("Copy Address") { copy(peer.id) }
                Divider()
                Button("Ban Peer…") { banning = peer }
            }
        }
        .scrollContentBackground(.hidden)
        .overlay {
            if peers.isEmpty {
                ContentUnavailableView("No connected peers", systemImage: "person.2",
                                       description: Text("Peers show up here while the torrent is connected to the swarm."))
            }
        }
        .safeAreaInset(edge: .bottom) {
            PaneBar {
                Button("Add Peers…", systemImage: "plus") { addingPeers = true }
                    .help("Connect to peers by address")
                    .disabled(torrent.state.isStopped)
            }
        }
        .sheet(isPresented: $addingPeers) {
            LinesSheet(title: "Add Peers", prompt: "203.0.113.5:6881",
                       footer: "One address and port per line. IPv6 addresses go in brackets, like [2001:db8::1]:6881.",
                       action: "Add") { lines in
                let hash = torrent.id
                model.run { try await $0.call("torrents/addPeers", ["hashes": hash, "peers": lines.joined(separator: "|")]) }
            }
        }
        .confirmationDialog("Ban \(banning?.address ?? "")?", isPresented: Binding(get: { banning != nil }, set: { if !$0 { banning = nil } }),
                            presenting: banning) { peer in
            Button("Ban Peer", role: .destructive) {
                model.run { try await $0.call("transfer/banPeers", ["peers": peer.id]) }
            }
        } message: { _ in
            Text("Sprout disconnects every peer at this address and refuses it on every torrent. Remove the ban in Settings › Privacy.")
        }
        .polling(id: torrent.id) {
            // Hold the list still while a ban is being confirmed.
            guard banning == nil else { return }
            if let loaded = try? await api.peers(hash: torrent.id) {
                peers = loaded.sorted {
                    let a = $0.downloadSpeed + $0.uploadSpeed, b = $1.downloadSpeed + $1.uploadSpeed
                    return a != b ? a > b : $0.id < $1.id
                }
            }
        }
    }
}

private func copy(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

// MARK: Trackers

private struct TrackersPane: View {
    @Environment(AppModel.self) private var model
    let torrent: Torrent
    let api: WebAPI

    @State private var trackers: [Tracker] = []
    @State private var webSeeds: [String] = []
    @State private var adding: Adding?
    @State private var editing: Tracker?
    @State private var editedURL = ""

    enum Adding: String, Identifiable {
        case trackers, webSeeds
        var id: Self { self }
    }

    private var pseudo: [Tracker] { trackers.filter(\.isPseudoTracker) }
    private var real: [Tracker] { trackers.filter { !$0.isPseudoTracker } }

    var body: some View {
        List {
            Section {
                ForEach(real) { tracker in
                    row(tracker).contextMenu {
                        Button("Copy URL") { copy(tracker.url) }
                        Button("Edit URL…") { editing = tracker }
                        Divider()
                        Button("Remove Tracker") { remove(tracker) }
                    }
                }
                if real.isEmpty {
                    Text(torrent.isPrivate ? "No trackers." : "No trackers. Peers come from DHT, peer exchange and local discovery.")
                        .foregroundStyle(.secondary)
                }
            }
            if !pseudo.isEmpty {
                Section("Discovery") {
                    ForEach(pseudo) { row($0) }
                }
            }
            if !webSeeds.isEmpty {
                Section("Web seeds") {
                    ForEach(webSeeds, id: \.self) { url in
                        Text(URL(string: url)?.host() ?? url)
                            .lineLimit(1)
                            .help(url)
                            .contextMenu {
                                Button("Copy URL") { copy(url) }
                                Divider()
                                Button("Remove Web Seed") { removeWebSeed(url) }
                            }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom) {
            PaneBar {
                Menu("Add", systemImage: "plus") {
                    Button("Add Trackers…") { adding = .trackers }
                    Button("Add Web Seeds…") { adding = .webSeeds }
                }
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Add trackers or web seeds")
            }
        }
        .sheet(item: $adding) { kind in
            switch kind {
            case .trackers:
                LinesSheet(title: "Add Trackers", prompt: "udp://tracker.example.org:1337/announce",
                           footer: "One per line. A blank line starts a new tier, tried only when the ones above fail.",
                           action: "Add", keepsBlankLines: true) { lines in
                    let hash = torrent.id
                    model.run { try await $0.call("torrents/addTrackers", ["hash": hash, "urls": lines.joined(separator: "\n")]) }
                }
            case .webSeeds:
                LinesSheet(title: "Add Web Seeds", prompt: "https://example.org/files/",
                           footer: "Web servers that host the same files, one per line.", action: "Add") { lines in
                    let hash = torrent.id
                    model.run { try await $0.call("torrents/addWebSeeds", ["hash": hash, "urls": lines.joined(separator: "|")]) }
                }
            }
        }
        .alert("Edit Tracker", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } }),
               presenting: editing) { tracker in
            TextField("URL", text: $editedURL)
            Button("Save") { edit(tracker) }
            Button("Cancel", role: .cancel) {}
        }
        .onChange(of: editing?.url) { editedURL = editing?.url ?? "" }
        .polling(id: torrent.id) { await load() }
    }

    private func row(_ tracker: Tracker) -> some View {
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

    private func load() async {
        async let loadedTrackers = try? api.trackers(hash: torrent.id)
        async let loadedSeeds = try? api.webSeeds(hash: torrent.id)
        if let list = await loadedTrackers { trackers = list }
        if let list = await loadedSeeds { webSeeds = list }
    }

    private func change(_ call: @escaping @MainActor (WebAPI) async throws -> Void) {
        model.run { api in
            try await call(api)
            await load()
        }
    }

    private func remove(_ tracker: Tracker) {
        let hash = torrent.id
        // The engine percent-decodes each URL here, so a "%" in a passkey must be encoded first.
        let encoded = tracker.url.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? tracker.url
        change { try await $0.call("torrents/removeTrackers", ["hash": hash, "urls": encoded]) }
    }

    private func edit(_ tracker: Tracker) {
        let url = editedURL.trimmingCharacters(in: .whitespacesAndNewlines)
        editing = nil
        guard !url.isEmpty, url != tracker.url else { return }
        let hash = torrent.id
        change { try await $0.call("torrents/editTracker", ["hash": hash, "url": tracker.url, "newUrl": url]) }
    }

    private func removeWebSeed(_ url: String) {
        let hash = torrent.id
        change { try await $0.call("torrents/removeWebSeeds", ["hash": hash, "urls": url]) }
    }
}

// MARK: Shared

/// The small action bar at the foot of an inspector list, like Finder's and Mail's.
private struct PaneBar<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 4) {
            content
            Spacer()
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

/// A sheet that takes a list, one entry per line.
struct LinesSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let prompt: String
    let footer: String
    let action: String
    /// Tracker lists use blank lines to separate tiers.
    var keepsBlankLines = false
    let submit: ([String]) -> Void

    @State private var text = ""

    private var lines: [String] {
        var list = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        if !keepsBlankLines { list.removeAll(where: \.isEmpty) }
        while list.first == "" { list.removeFirst() }
        while list.last == "" { list.removeLast() }
        return list
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: title)
            Form {
                Section {
                    LinesEditor(text: $text, placeholder: prompt, minHeight: 90)
                        .accessibilityLabel(title)
                } footer: {
                    Text(footer)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(action) {
                    submit(lines)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(lines.isEmpty)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 440)
    }
}
