import AppKit
import UniformTypeIdentifiers
import OSLog
import UserNotifications
import Observation

@MainActor @Observable
final class AppModel {
    let engine = EngineController()

    private(set) var torrents: [String: Torrent] = [:]
    private(set) var server = ServerState()
    private(set) var categories: [String] = []
    /// Each category's own folder; empty means the default folder.
    private(set) var categoryFolders: [String: String] = [:]
    private(set) var tags: [String] = []
    /// Whether adding a torrent that's already in the list merges its trackers (engine `merge_trackers`).
    var mergesTrackers = true
    /// A short message shown over the list, e.g. after adding a torrent that was already there.
    var notice: Notice?
    /// Torrents whose speed and seeding limits are being edited.
    var pendingLimits: Set<String>?
    /// The category whose folder is being edited.
    var editingCategory: String?
    var showsCreateSheet = false
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
        await applyFirstRunDefaults(api)
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

    /// The engine ships with tracker merging off, so adding a torrent twice just fails.
    /// Sprout turns it on once; after that the Settings switch decides.
    private func applyFirstRunDefaults(_ api: WebAPI) async {
        let key = "AppliedEngineDefaults"
        if !UserDefaults.standard.bool(forKey: key) {
            if (try? await api.setPreferences(["merge_trackers": .bool(true)])) != nil {
                UserDefaults.standard.set(true, forKey: key)
            }
        }
        if let prefs = try? await api.preferences() { mergesTrackers = prefs["merge_trackers"]?.bool ?? false }
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
        if update["full_update"]?.bool == true { categoryFolders = [:] }
        var names = Set(categories), labels = Set(tags)
        for (name, info) in update["categories"]?.object ?? [:] {
            names.insert(name)
            if let path = info["savePath"]?.string { categoryFolders[name] = path }
        }
        for removed in (update["categories_removed"]?.array ?? []).compactMap(\.string) {
            names.remove(removed)
            categoryFolders[removed] = nil
        }
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
        // Links to .torrent files on the web can't be checked before the engine fetches them.
        let unique = Array(Set(links))
        let known = unique.map { Magnet.infoHash($0).flatMap(existingTorrentID) }
        let allKnown = !known.contains(nil)
        perform { [self] api in
            try await Self.adding(allKnown: allKnown) { try await api.add(urls: unique, options: options) }
            reportDuplicates(Set(known.compactMap { $0 }))
        }
    }

    func add(files: [URL], options: AddOptions = AddOptions()) {
        perform { [self] api in
            let parsed = (try? await api.parseMetadata(files)) ?? []
            let known = parsed.map { entry in
                [entry["hash"]?.string, entry["infohash_v1"]?.string, entry["infohash_v2"]?.string]
                    .compactMap { $0 }.lazy.compactMap(self.existingTorrentID).first
            }
            // Two copies of one file count once; every file must be recognised to treat a refusal as a duplicate.
            let allKnown = parsed.count == files.count && !known.contains(nil)
            try await Self.adding(allKnown: allKnown) { try await api.add(torrentFiles: files, options: options) }
            reportDuplicates(Set(known.compactMap { $0 }))
        }
    }

    /// The torrent in the list that has this hash as its ID or as its v1 or v2 info hash.
    private func existingTorrentID(_ hash: String) -> String? {
        let hash = hash.lowercased()
        if torrents[hash] != nil { return hash }
        return torrents.values.first { $0.knownHashes.contains(hash) }?.id
    }

    /// torrents/add answers 409 when nothing in the request was added. When every item was
    /// already in the list that is expected, and the duplicate notice explains it.
    private static func adding(allKnown: Bool, _ add: () async throws -> Void) async throws {
        do {
            try await add()
        } catch let error as WebAPI.HTTPError where error.status == 409 {
            if !allKnown { throw AddError() }
        }
    }

    private struct AddError: LocalizedError {
        var errorDescription: String? { "The engine didn't add it. Check that the link or file is a valid torrent." }
    }

    /// Selects torrents that were added again and says what the engine did with them.
    private func reportDuplicates(_ hashes: Set<String>) {
        let existing = hashes.compactMap { torrents[$0] }
        guard let first = existing.first else { return }
        sidebar = .state(.all)
        selection = Set(existing.map(\.id))
        let name = existing.count == 1 ? "“\(first.name)” is" : "\(existing.count) of these torrents are"
        let result: String
        if !mergesTrackers {
            result = "Nothing was added. Turn on tracker merging in Settings › Downloads to combine their trackers."
        } else if existing.allSatisfy(\.isPrivate) {
            result = "Private torrents keep their own trackers, so nothing was merged."
        } else {
            result = existing.count == 1
                ? "Its trackers and web seeds were merged into the one you have."
                : "Their trackers and web seeds were merged into the ones you have."
        }
        notice = Notice(title: "\(name) already in your list", detail: result)
    }

    func copyMagnetLinks(_ hashes: Set<String>) {
        let links = hashes.compactMap { torrents[$0]?.magnetURI }.filter { !$0.isEmpty }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(links.joined(separator: "\n"), forType: .string)
    }

    /// Saves a torrent's .torrent file where the user picks. The save panel asks before replacing a file.
    func exportTorrentFile(_ torrent: Torrent) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(torrent.name).torrent"
        panel.allowedContentTypes = [.init(filenameExtension: "torrent") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        perform { api in
            let data = try await api.fetch("torrents/export", ["hash": torrent.id])
            try data.write(to: url)
        }
    }

    func setFlag(_ action: String, _ on: Bool, on hashes: Set<String>, key: String = "value") {
        perform { try await $0.torrents(action, hashes, [key: String(on)]) }
    }

    /// Sets only the limits passed; nil leaves that limit as each torrent has it.
    func setLimits(on hashes: Set<String>, download: Int64?, upload: Int64?, share: ShareLimits?) {
        pendingLimits = nil
        perform { api in
            if let download { try await api.torrents("setDownloadLimit", hashes, ["limit": String(download)]) }
            if let upload { try await api.torrents("setUploadLimit", hashes, ["limit": String(upload)]) }
            if let share {
                try await api.torrents("setShareLimits", hashes, [
                    "ratioLimit": String(share.ratio),
                    "seedingTimeLimit": String(Int(share.seedingTime)),
                    "inactiveSeedingTimeLimit": String(Int(share.inactiveTime)),
                    "shareLimitAction": ShareLimits.actionNames[share.action] ?? "Default",
                    "shareLimitsMode": share.mode,
                ])
            }
        }
    }

    /// The engine turns off "Use Category Folder" for a category's torrents when its folder changes,
    /// so nothing moves. Sprout turns it back on for the torrents that had it, so they follow the folder.
    func setCategoryFolder(_ category: String, to folder: String) {
        editingCategory = nil
        let following = Set(torrents.values.filter { $0.category == category && $0.usesCategoryFolder }.map(\.id))
        perform { api in
            try await api.call("torrents/editCategory", ["category": category, "savePath": folder])
            if !following.isEmpty { try await api.torrents("setAutoManagement", following, ["enable": "true"]) }
        }
    }

    /// Asked for from the sidebar; the main window confirms before anything is removed.
    var pendingCategoryRemoval: String?

    func removeCategory(_ name: String) {
        pendingCategoryRemoval = nil
        if sidebar == .category(name) { sidebar = .state(.all) }
        perform { try await $0.call("torrents/removeCategories", ["categories": name]) }
    }

    func removeTag(_ name: String) {
        if sidebar == .tag(name) { sidebar = .state(.all) }
        perform { try await $0.call("torrents/deleteTags", ["tags": name]) }
    }

    /// Runs an engine call from a view and reports a failure the same way as menu actions.
    func run(_ action: @escaping @MainActor (WebAPI) async throws -> Void) {
        perform(action)
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

    private func perform(_ action: @escaping @MainActor (WebAPI) async throws -> Void) {
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

/// A passing message, not an error: it explains what just happened and goes away by itself.
struct Notice: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let detail: String
}

/// Reads the info hash out of a magnet link, as the lowercase hex the engine uses for IDs.
enum Magnet {
    static func infoHash(_ link: String) -> String? {
        guard let items = URLComponents(string: link)?.queryItems, link.lowercased().hasPrefix("magnet:") else { return nil }
        for item in items where item.name == "xt" {
            guard let value = item.value?.lowercased() else { continue }
            // v2 links: "urn:btmh:1220" then the 64-hex SHA-256 info hash.
            if value.hasPrefix("urn:btmh:1220") {
                let hash = String(value.dropFirst("urn:btmh:1220".count))
                if hash.count == 64, hash.allSatisfy(\.isHexDigit) { return hash }
                continue
            }
            guard value.hasPrefix("urn:btih:") else { continue }
            let hash = String(value.dropFirst("urn:btih:".count))
            if hash.count == 40, hash.allSatisfy(\.isHexDigit) { return hash }
            if hash.count == 32, let hex = base32ToHex(hash) { return hex }
        }
        return nil
    }

    private static func base32ToHex(_ text: String) -> String? {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz234567")
        var bits = 0, value = 0
        var bytes: [UInt8] = []
        for char in text {
            guard let index = alphabet.firstIndex(of: char) else { return nil }
            value = (value << 5) | index
            bits += 5
            if bits >= 8 {
                bytes.append(UInt8((value >> (bits - 8)) & 0xFF))
                bits -= 8
            }
        }
        return bytes.count == 20 ? bytes.map { String(format: "%02x", $0) }.joined() : nil
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
