import AppKit
import Observation

@MainActor @Observable
final class AppModel {
    let engine = EngineController()

    private(set) var torrents: [String: Torrent] = [:]
    private(set) var server = ServerState()
    /// One sample per sync (about a second), newest last; the pulse band draws the last minute.
    private(set) var speedHistory: [SpeedSample] = []
    private var rawTorrents: [String: [String: JSON]] = [:]
    private var rid = 0
    private var syncTask: Task<Void, Never>?
    private var pendingOpens: [URL] = []

    var filter: TorrentFilter = .all
    var searchText = ""
    var selection = Set<String>()
    var sortKey: SortKey = .added
    var sortAscending = false
    var showsInspector = true
    var showsAddSheet = false
    var pendingRemoval: Set<String>?
    var errorMessage: String?

    var visibleTorrents: [Torrent] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return torrents.values
            .filter { filter.includes($0) && (query.isEmpty || $0.name.localizedStandardContains(query)) }
            .sorted(using: sortKey.comparator(ascending: sortAscending))
    }

    func count(_ filter: TorrentFilter) -> Int {
        torrents.values.count(where: filter.includes)
    }

    var selectedTorrents: [Torrent] { selection.compactMap { torrents[$0] } }

    // MARK: Lifecycle

    func start() async {
        await engine.start()
        guard let api = engine.api else { return }
        syncTask?.cancel()
        syncTask = Task { await syncLoop(api) }
        if !pendingOpens.isEmpty {
            let urls = pendingOpens
            pendingOpens = []
            open(urls)
        }
    }

    func shutdown() async {
        syncTask?.cancel()
        await engine.stop()
    }

    private func syncLoop(_ api: WebAPI) async {
        while !Task.isCancelled {
            do {
                apply(try await api.mainData(rid: rid))
            } catch is CancellationError {
                return
            } catch {
                // The engine's own exit is reported by EngineController; a slow reply just retries.
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func apply(_ update: JSON) {
        if update["full_update"]?.bool == true {
            rawTorrents = [:]
        }
        rid = Int(update["rid"]?.double ?? 0)
        for (hash, changes) in update["torrents"]?.object ?? [:] {
            rawTorrents[hash, default: [:]].merge(changes.object ?? [:]) { $1 }
        }
        for removed in update["torrents_removed"]?.array ?? [] {
            if let hash = removed.string { rawTorrents[hash] = nil }
        }
        if let changes = update["server_state"]?.object {
            var merged = serverFields
            merged.merge(changes) { $1 }
            serverFields = merged
            server = ServerState(fields: merged)
        }
        speedHistory.append(SpeedSample(down: server.downloadSpeed, up: server.uploadSpeed))
        if speedHistory.count > 180 { speedHistory.removeFirst(speedHistory.count - 180) }
        torrents = rawTorrents.reduce(into: [:]) { $0[$1.key] = Torrent(hash: $1.key, fields: $1.value) }
        selection.formIntersection(torrents.keys)
        #if DEBUG
        // Launch with -SproutSelectFirst YES to inspect the first torrent without clicking.
        if selection.isEmpty, UserDefaults.standard.bool(forKey: "SproutSelectFirst"), let first = visibleTorrents.first {
            selection = [first.id]
        }
        #endif
        updateDockBadge()
    }

    private var serverFields: [String: JSON] = [:]

    private func updateDockBadge() {
        let downloading = torrents.values.count { $0.state.isDownloading && !$0.state.isStopped }
        NSApp.dockTile.badgeLabel = downloading > 0 ? String(downloading) : nil
    }

    // MARK: Actions

    /// Adds magnet links and .torrent files opened from the browser, Finder or a drop.
    func open(_ urls: [URL]) {
        guard engine.api != nil else {
            pendingOpens.append(contentsOf: urls)
            return
        }
        let magnets = urls.filter { $0.scheme == "magnet" || $0.scheme == "http" || $0.scheme == "https" }
        let files = urls.filter { $0.isFileURL && $0.pathExtension.lowercased() == "torrent" }
        if !magnets.isEmpty { add(links: magnets.map(\.absoluteString)) }
        if !files.isEmpty { add(files: files) }
    }

    func add(links: [String], savePath: String? = nil, startNow: Bool = true) {
        perform { try await $0.add(urls: links, savePath: savePath, stopped: !startNow) }
    }

    func add(files: [URL], savePath: String? = nil, startNow: Bool = true) {
        perform { try await $0.add(torrentFiles: files, savePath: savePath, stopped: !startNow) }
    }

    func startSelected() {
        let hashes = selection
        perform { try await $0.start(hashes) }
    }

    func stopSelected() {
        let hashes = selection
        perform { try await $0.stop(hashes) }
    }

    func requestRemoveSelected() {
        if !selection.isEmpty { pendingRemoval = selection }
    }

    func remove(_ hashes: Set<String>, deleteFiles: Bool) {
        pendingRemoval = nil
        perform { try await $0.delete(hashes, deleteFiles: deleteFiles) }
    }

    func revealInFinder(_ torrent: Torrent) {
        let path = torrent.contentPath.isEmpty ? torrent.savePath : torrent.contentPath
        NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: path)])
    }

    var canStart: Bool { selectedTorrents.contains { $0.state.isStopped } }
    var canStop: Bool { selectedTorrents.contains { !$0.state.isStopped } }

    private func perform(_ action: @escaping @Sendable (WebAPI) async throws -> Void) {
        guard let api = engine.api else { return }
        Task {
            do {
                try await action(api)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
