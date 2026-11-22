import Foundation

struct Torrent: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var state: TorrentState
    var size: Int64
    var progress: Double
    var downloadSpeed: Int64
    var uploadSpeed: Int64
    /// Seconds remaining; qBittorrent reports 8640000 for "unknown".
    var eta: Int64
    var ratio: Double
    var addedOn: Date
    var savePath: String
    var contentPath: String
    var seeds: Int64
    var peers: Int64
    var category: String
    var tags: [String]
    /// Queue position, or -1 when queueing is off or the torrent is finished.
    var queuePosition: Int64
    var isSequential: Bool
    var isForced: Bool
    var magnetURI: String
    /// Bytes per second; 0 means no limit of its own.
    var downloadLimit: Int64
    var uploadLimit: Int64
    var shareLimits: ShareLimits
    var isSuperSeeding: Bool
    var usesCategoryFolder: Bool
    var firstLastPiecesFirst: Bool
    var isPrivate: Bool
    var hasMetadata: Bool
    /// The real info hashes. `id` is the engine's torrent ID, which for v2 and hybrid torrents
    /// is a truncated SHA-256, not either info hash.
    var infoHashV1: String
    var infoHashV2: String

    init(hash: String, fields: [String: JSON]) {
        id = hash
        name = fields.string("name")
        state = TorrentState(rawValue: fields.string("state")) ?? .unknown
        size = fields.int("size")
        progress = fields.double("progress")
        downloadSpeed = fields.int("dlspeed")
        uploadSpeed = fields.int("upspeed")
        eta = fields.int("eta")
        ratio = fields.double("ratio")
        addedOn = Date(timeIntervalSince1970: fields.double("added_on"))
        savePath = fields.string("save_path")
        contentPath = fields.string("content_path")
        seeds = fields.int("num_seeds")
        peers = fields.int("num_leechs")
        category = fields.string("category")
        tags = fields.string("tags").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        queuePosition = fields["priority"]?.int ?? -1
        isSequential = fields["seq_dl"]?.bool ?? false
        isForced = fields["force_start"]?.bool ?? false
        magnetURI = fields.string("magnet_uri")
        downloadLimit = max(0, fields.int("dl_limit"))
        uploadLimit = max(0, fields.int("up_limit"))
        shareLimits = ShareLimits(fields: fields)
        isSuperSeeding = fields["super_seeding"]?.bool ?? false
        usesCategoryFolder = fields["auto_tmm"]?.bool ?? false
        firstLastPiecesFirst = fields["f_l_piece_prio"]?.bool ?? false
        isPrivate = fields["private"]?.bool ?? false
        hasMetadata = fields["has_metadata"]?.bool ?? true
        // The engine sends "" or "-" style values when a version is absent.
        infoHashV1 = Self.hash(fields.string("infohash_v1"), length: 40)
        infoHashV2 = Self.hash(fields.string("infohash_v2"), length: 64)
    }

    private static func hash(_ value: String, length: Int) -> String {
        value.count == length && value.allSatisfy(\.isHexDigit) ? value.lowercased() : ""
    }

    /// Every hash a duplicate could be recognised by.
    var knownHashes: [String] { [id, infoHashV1, infoHashV2].filter { !$0.isEmpty } }

    /// The hash people share and sites list: v1 when there is one.
    var displayHash: String { infoHashV1.isEmpty ? (infoHashV2.isEmpty ? id : infoHashV2) : infoHashV1 }

    var isTransferring: Bool { downloadSpeed > 0 || uploadSpeed > 0 }
    var hasKnownETA: Bool { eta > 0 && eta < 8_640_000 && progress < 1 }
    var etaSortKey: Int64 { hasKnownETA ? eta : .max }
}

enum TorrentState: String, Sendable {
    case error, missingFiles, uploading, stoppedUP, queuedUP, stalledUP, checkingUP, forcedUP
    case allocating, downloading, metaDL, forcedMetaDL, stoppedDL, queuedDL, stalledDL, checkingDL, forcedDL
    case checkingResumeData, moving, unknown

    var label: String {
        switch self {
        case .downloading, .forcedDL: "Downloading"
        case .metaDL, .forcedMetaDL: "Fetching metadata"
        case .stalledDL: "Waiting for peers"
        case .queuedDL, .queuedUP: "Queued"
        case .checkingDL, .checkingUP, .checkingResumeData: "Checking"
        case .allocating: "Allocating"
        case .uploading, .forcedUP, .stalledUP: "Seeding"
        case .stoppedDL: "Stopped"
        case .stoppedUP: "Completed"
        case .error: "Error"
        case .missingFiles: "Files missing"
        case .moving: "Moving"
        case .unknown: "Unknown"
        }
    }

    var symbol: String {
        switch self {
        case .downloading, .forcedDL: "arrow.down.circle"
        case .metaDL, .forcedMetaDL: "ellipsis.circle"
        case .stalledDL: "hourglass"
        case .queuedDL, .queuedUP: "clock"
        case .checkingDL, .checkingUP, .checkingResumeData, .allocating, .moving: "arrow.triangle.2.circlepath"
        case .uploading, .forcedUP, .stalledUP: "arrow.up.circle"
        case .stoppedDL: "stop.circle"
        case .stoppedUP: "checkmark.circle"
        case .error, .missingFiles: "exclamationmark.triangle"
        case .unknown: "questionmark.circle"
        }
    }

    var isError: Bool { self == .error || self == .missingFiles }
    var isStopped: Bool { self == .stoppedDL || self == .stoppedUP }
    var isChecking: Bool { self == .checkingDL || self == .checkingUP || self == .checkingResumeData }
    var isDownloading: Bool {
        switch self {
        case .downloading, .forcedDL, .metaDL, .forcedMetaDL, .stalledDL, .queuedDL, .checkingDL, .allocating: true
        default: false
        }
    }
    var isSeeding: Bool {
        switch self {
        case .uploading, .forcedUP, .stalledUP, .queuedUP, .checkingUP: true
        default: false
        }
    }
}

/// Sidebar filters, matching qBittorrent's own state filters.
enum TorrentFilter: String, CaseIterable, Identifiable {
    case all, downloading, seeding, completed, stopped, errored

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "All"
        case .downloading: "Downloading"
        case .seeding: "Seeding"
        case .completed: "Completed"
        case .stopped: "Stopped"
        case .errored: "Errors"
        }
    }

    var symbol: String {
        switch self {
        case .all: "tray.full"
        case .downloading: "arrow.down.circle"
        case .seeding: "arrow.up.circle"
        case .completed: "checkmark.circle"
        case .stopped: "stop.circle"
        case .errored: "exclamationmark.triangle"
        }
    }

    func includes(_ torrent: Torrent) -> Bool {
        switch self {
        case .all: true
        case .downloading: torrent.state.isDownloading
        case .seeding: torrent.state.isSeeding
        case .completed: torrent.progress >= 1
        case .stopped: torrent.state.isStopped
        case .errored: torrent.state.isError
        }
    }
}

/// What the sidebar has selected: a state filter, a category, or a tag.
enum SidebarItem: Hashable {
    case state(TorrentFilter)
    case category(String)
    case tag(String)

    var title: String {
        switch self {
        case .state(let filter): filter.title
        case .category(let name): name.isEmpty ? "Uncategorized" : name
        case .tag(let name): name
        }
    }

    var symbol: String {
        switch self {
        case .state(let filter): filter.symbol
        case .category: "folder"
        case .tag: "tag"
        }
    }

    func includes(_ torrent: Torrent) -> Bool {
        switch self {
        case .state(let filter): filter.includes(torrent)
        case .category(let name): torrent.category == name
        case .tag(let name): torrent.tags.contains(name)
        }
    }
}

struct ServerState: Sendable {
    var downloadSpeed: Int64 = 0
    var uploadSpeed: Int64 = 0
    var freeSpace: Int64 = 0
    var connection = ""
    var usesAlternativeSpeeds = false
    var queueingEnabled = false

    init() {}

    init(fields: [String: JSON]) {
        downloadSpeed = fields.int("dl_info_speed")
        uploadSpeed = fields.int("up_info_speed")
        freeSpace = fields.int("free_space_on_disk")
        connection = fields.string("connection_status")
        usesAlternativeSpeeds = fields["use_alt_speed_limits"]?.bool ?? false
        queueingEnabled = fields["queueing"]?.bool ?? false
    }
}

enum FilePriority: Int, CaseIterable, Identifiable, Sendable {
    case skip = 0, normal = 1, high = 6, maximum = 7

    var id: Self { self }

    var title: String {
        switch self {
        case .skip: "Don't Download"
        case .normal: "Normal"
        case .high: "High"
        case .maximum: "Maximum"
        }
    }
}

struct TorrentFile: Identifiable, Sendable {
    let id: Int
    let name: String
    let size: Int64
    let progress: Double
    var priority: FilePriority

    init(fields: [String: JSON]) {
        id = Int(fields.int("index"))
        name = fields.string("name")
        size = fields.int("size")
        progress = fields.double("progress")
        priority = FilePriority(rawValue: Int(fields.int("priority"))) ?? .normal
    }
}

struct Tracker: Identifiable, Sendable {
    var id: String { url }
    let url: String
    let status: Int
    let isUpdating: Bool
    let seeds: Int64
    let peers: Int64
    let message: String

    init(fields: [String: JSON]) {
        url = fields.string("url")
        status = Int(fields.int("status"))
        isUpdating = fields["updating"]?.bool ?? false
        seeds = fields.int("num_seeds")
        peers = fields.int("num_peers")
        message = fields.string("msg")
    }

    /// DHT, PeX and LSD are listed as pseudo-trackers like "** [DHT] **".
    var isPseudoTracker: Bool { url.hasPrefix("** [") }

    var displayName: String {
        if isPseudoTracker { return url.replacingOccurrences(of: "** [", with: "").replacingOccurrences(of: "] **", with: "") }
        // The port too, so two trackers on one host stay tellable apart.
        guard let parsed = URL(string: url), let host = parsed.host() else { return url }
        return parsed.port.map { "\(host):\($0)" } ?? host
    }

    var statusLabel: String {
        if isUpdating { return "Updating" }
        return switch status {
        case 0: "Disabled"
        case 1: "Not contacted"
        case 2: "Working"
        case 4: "Not working"
        case 5: "Tracker error"
        case 6: "Unreachable"
        default: "Unknown"
        }
    }

    var isFailing: Bool { [4, 5, 6].contains(status) }
}

struct Peer: Identifiable, Sendable {
    let id: String
    let client: String
    let progress: Double
    let downloadSpeed: Int64
    let uploadSpeed: Int64
    let countryCode: String

    /// The IP without the port: bans apply to the whole address.
    var address: String {
        if id.hasPrefix("["), let end = id.firstIndex(of: "]") { return String(id[id.index(after: id.startIndex)..<end]) }
        return id.split(separator: ":").count == 2 ? String(id.split(separator: ":")[0]) : id
    }

    init(id: String, fields: [String: JSON]) {
        self.id = id
        client = fields.string("client")
        progress = fields.double("progress")
        downloadSpeed = fields.int("dl_speed")
        uploadSpeed = fields.int("up_speed")
        countryCode = fields.string("country_code").uppercased()
    }
}

/// A torrent's own seeding limits. The engine uses -2 for "follow Settings" and -1 for "no limit".
struct ShareLimits: Hashable, Sendable {
    static let followSettings = -2.0
    static let none = -1.0

    var ratio: Double
    /// Minutes.
    var seedingTime: Double
    /// Minutes without any upload.
    var inactiveTime: Double
    /// -1 follows Settings; 0 stop, 1 remove, 3 remove with files, 2 super seeding.
    var action: Int
    /// "Default", "MatchAny" or "MatchAll": whether any limit or all of them stop seeding.
    var mode = "Default"

    /// The engine reads and writes the action by its enum name.
    static let actionNames = [-1: "Default", 0: "Stop", 1: "Remove", 3: "RemoveWithContent", 2: "EnableSuperSeeding"]

    init(ratio: Double = followSettings, seedingTime: Double = followSettings, inactiveTime: Double = followSettings, action: Int = -1) {
        self.ratio = ratio
        self.seedingTime = seedingTime
        self.inactiveTime = inactiveTime
        self.action = action
    }

    init(fields: [String: JSON]) {
        ratio = fields["ratio_limit"]?.double ?? Self.followSettings
        seedingTime = fields["seeding_time_limit"]?.double ?? Self.followSettings
        inactiveTime = fields["inactive_seeding_time_limit"]?.double ?? Self.followSettings
        let actionName = fields.string("share_limit_action")
        action = Self.actionNames.first { $0.value == actionName }?.key ?? -1
        mode = fields["share_limits_mode"]?.string ?? "Default"
    }

    var followsSettings: Bool {
        ratio == Self.followSettings && seedingTime == Self.followSettings && inactiveTime == Self.followSettings
    }

    var isUnlimited: Bool { ratio == Self.none && seedingTime == Self.none && inactiveTime == Self.none }

    /// e.g. "Ratio 2.00 or 24 h seeding", "From Settings", "None".
    var summary: String {
        if followsSettings { return "From Settings" }
        var parts: [String] = []
        if ratio >= 0 { parts.append("ratio \(ratio.formatted(.number.precision(.fractionLength(2))))") }
        if seedingTime >= 0 { parts.append("\(Format.duration(seconds: Int64(seedingTime) * 60)) seeding") }
        if inactiveTime >= 0 { parts.append("\(Format.duration(seconds: Int64(inactiveTime) * 60)) idle") }
        guard let first = parts.first else { return "None" }
        return ([first.prefix(1).uppercased() + first.dropFirst()] + parts.dropFirst()).joined(separator: " or ")
    }
}

struct SpeedSample: Sendable {
    var down: Int64 = 0
    var up: Int64 = 0
}

enum SortKey: String, CaseIterable, Identifiable {
    case added, name, progress, downloadSpeed, uploadSpeed, timeLeft, size

    var id: Self { self }

    var title: String {
        switch self {
        case .added: "Date Added"
        case .name: "Name"
        case .progress: "Progress"
        case .downloadSpeed: "Download Speed"
        case .uploadSpeed: "Upload Speed"
        case .timeLeft: "Time Left"
        case .size: "Size"
        }
    }

    func comparator(ascending: Bool) -> KeyPathComparator<Torrent> {
        let order: SortOrder = ascending ? .forward : .reverse
        return switch self {
        case .added: KeyPathComparator(\.addedOn, order: order)
        case .name: KeyPathComparator(\.name, comparator: .localizedStandard, order: order)
        case .progress: KeyPathComparator(\.progress, order: order)
        case .downloadSpeed: KeyPathComparator(\.downloadSpeed, order: order)
        case .uploadSpeed: KeyPathComparator(\.uploadSpeed, order: order)
        case .timeLeft: KeyPathComparator(\.etaSortKey, order: order)
        case .size: KeyPathComparator(\.size, order: order)
        }
    }
}
