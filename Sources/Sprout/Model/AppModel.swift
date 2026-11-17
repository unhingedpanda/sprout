import AppKit
import OSLog
import UserNotifications
import Observation

@MainActor @Observable
final class AppModel {
    let engine = EngineController()

    private(set) var torrents: [String: Torrent] = [:]
    private(set) var server = ServerState()
    private(set) var categories: [String] = []
    private(set) var tags: [String] = []
    /// One sample per sync (about a second), newest last; the pulse band draws the last minute.
    private(set) var speedHistory: [SpeedSample] = []
    private var rawTorrents: [String: [String: JSON]] = [:]
    private var rid = 0
    private var syncTask: Task<Void, Never>?
    private var pendingOpens: [URL] = []

    var sidebar: SidebarItem = .state(.all)
    var searchText = ""
    var selection = Set<String>()
    var sortKey: SortKey = .added
    var sortAscending = false
    var showsInspector = true
    var showsAddSheet = false
    var pendingRemoval: Set<String>?
    var errorMessage: String?
    /// A question that needs a typed answer: a new name, category or tag.
    var prompt: TextPrompt?
    /// Torrents waiting for a folder to move to.
    var pendingMove: Set<String>?
    private var sleepActivity: NSObjectProtocol?
    private var hasSynced = false

    var visibleTorrents: [Torrent] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return torrents.values
            .filter { sidebar.includes($0) && (query.isEmpty || $0.name.localizedStandardContains(query)) }
            .sorted(using: sortKey.comparator(ascending: sortAscending))
    }

    func count(_ item: SidebarItem) -> Int {
        torrents.values.count(where: item.includes)
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
            categories = []
            tags = []
        }
        rid = Int(update["rid"]?.double ?? 0)
        for (hash, changes) in update["torrents"]?.object ?? [:] {
            rawTorrents[hash, default: [:]].merge(changes.object ?? [:]) { $1 }
        }
        for removed in update["torrents_removed"]?.array ?? [] {
            if let hash = removed.string { rawTorrents[hash] = nil }
        }
        var names = Set(categories), labels = Set(tags)
        names.formUnion(update["categories"]?.object?.keys.map { $0 } ?? [])
        names.subtract((update["categories_removed"]?.array ?? []).compactMap(\.string))
        labels.formUnion((update["tags"]?.array ?? []).compactMap(\.string))
        labels.subtract((update["tags_removed"]?.array ?? []).compactMap(\.string))
        categories = names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        tags = labels.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        if let changes = update["server_state"]?.object {
            var merged = serverFields
            merged.merge(changes) { $1 }
            serverFields = merged
            server = ServerState(fields: merged)
        }
        speedHistory.append(SpeedSample(down: server.downloadSpeed, up: server.uploadSpeed))
        if speedHistory.count > 180 { speedHistory.removeFirst(speedHistory.count - 180) }
        let previous = torrents
        torrents = rawTorrents.reduce(into: [:]) { $0[$1.key] = Torrent(hash: $1.key, fields: $1.value) }
        selection.formIntersection(torrents.keys)
        if hasSynced { notifyFinished(since: previous) }
        hasSynced = true
        holdSleepWhileDownloading()
        #if DEBUG
        // Launch with -SproutSelectFirst YES to inspect the first torrent without clicking.
        if selection.isEmpty, UserDefaults.standard.bool(forKey: "SproutSelectFirst"), let first = visibleTorrents.first {
            selection = [first.id]
        }
        #endif
        updateDockBadge()
    }

    private var serverFields: [String: JSON] = [:]
    private static let log = Logger(subsystem: "dev.unhingedpanda.Sprout", category: "notifications")

    // MARK: System integration

    /// Posts "Download finished" for torrents that crossed 100% since the last sync.
    private func notifyFinished(since previous: [String: Torrent]) {
        guard Preferences.notifyOnCompletion else { return }
        for torrent in torrents.values where torrent.progress >= 1 {
            // A recheck also climbs to 100%; only a real download counts.
            guard let before = previous[torrent.id], before.progress < 1, !before.state.isChecking else { continue }
            let content = UNMutableNotificationContent()
            content.title = "Download finished"
            content.body = torrent.name
            content.userInfo = ["hash": torrent.id]
            let request = UNNotificationRequest(identifier: torrent.id, content: content, trigger: nil)
            Task {
                do {
                    try await UNUserNotificationCenter.current().add(request)
                    Self.log.notice("Posted finished notification for \(torrent.id, privacy: .public)")
                } catch {
                    Self.log.error("Finished notification failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    /// Keeps the Mac awake while anything is downloading, if the user wants that.
    func holdSleepWhileDownloading() {
        // Only states where data is flowing: a torrent stuck waiting for peers must not keep the Mac up.
        let active: Set<TorrentState> = [.downloading, .forcedDL, .metaDL, .forcedMetaDL]
        let downloading = torrents.values.contains { active.contains($0.state) }
        if downloading && Preferences.preventSleep {
            if sleepActivity == nil {
                sleepActivity = ProcessInfo.processInfo.beginActivity(options: .idleSystemSleepDisabled, reason: "Downloading torrents")
            }
        } else if let activity = sleepActivity {
            ProcessInfo.processInfo.endActivity(activity)
            sleepActivity = nil
        }
    }

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

    func add(links: [String], options: AddOptions = AddOptions()) {
        perform { try await $0.add(urls: links, options: options) }
    }

    func add(files: [URL], options: AddOptions = AddOptions()) {
        perform { try await $0.add(torrentFiles: files, options: options) }
    }

    func start(_ hashes: Set<String>) {
        perform { try await $0.start(hashes) }
    }

    func stop(_ hashes: Set<String>) {
        perform { try await $0.stop(hashes) }
    }

    func requestRemove(_ hashes: Set<String>) {
        if !hashes.isEmpty { pendingRemoval = hashes }
    }

    func startSelected() { start(selection) }
    func stopSelected() { stop(selection) }
    func requestRemoveSelected() { requestRemove(selection) }

    func remove(_ hashes: Set<String>, deleteFiles: Bool) {
        pendingRemoval = nil
        perform { try await $0.delete(hashes, deleteFiles: deleteFiles) }
    }

    func revealInFinder(_ torrent: Torrent) {
        let path = torrent.contentPath.isEmpty ? torrent.savePath : torrent.contentPath
        NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: path)])
    }

    func forceStart(_ hashes: Set<String>, _ on: Bool) {
        perform { try await $0.torrents("setForceStart", hashes, ["value": String(on)]) }
    }

    /// recheck, reannounce, toggleSequentialDownload, topPrio, increasePrio, decreasePrio, bottomPrio.
    func run(_ action: String, on hashes: Set<String>) {
        perform { try await $0.torrents(action, hashes) }
    }

    func move(_ hashes: Set<String>, to folder: URL) {
        pendingMove = nil
        perform { try await $0.torrents("setLocation", hashes, ["location": folder.path]) }
    }

    func setCategory(_ category: String, on hashes: Set<String>) {
        perform { api in
            try await api.torrents("setCategory", hashes, ["category": category])
        }
    }

    func setTag(_ tag: String, _ on: Bool, on hashes: Set<String>) {
        perform { try await $0.torrents(on ? "addTags" : "removeTags", hashes, ["tags": tag]) }
    }

    func toggleAlternativeSpeeds() {
        perform { try await $0.toggleAlternativeSpeeds() }
    }

    /// Applies the typed answer to the current prompt.
    func answer(_ prompt: TextPrompt, with text: String) {
        self.prompt = nil
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        switch prompt.kind {
        case .rename(let hash):
            perform { try await $0.rename(hash: hash, to: value) }
        case .newCategory(let hashes):
            perform { api in
                try await api.createCategory(value)
                if !hashes.isEmpty { try await api.torrents("setCategory", hashes, ["category": value]) }
            }
        case .newTag(let hashes):
            perform { api in
                try await api.createTags([value])
                if !hashes.isEmpty { try await api.torrents("addTags", hashes, ["tags": value]) }
            }
        }
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

/// A question that needs a typed answer.
struct TextPrompt: Identifiable {
    enum Kind {
        case rename(String)
        case newCategory(Set<String>)
        case newTag(Set<String>)
    }

    let id = UUID()
    let kind: Kind
    var initial = ""

    var title: String {
        switch kind {
        case .rename: "Rename Torrent"
        case .newCategory: "New Category"
        case .newTag: "New Tag"
        }
    }

    var action: String {
        switch kind {
        case .rename: "Rename"
        case .newCategory, .newTag: "Create"
        }
    }
}
