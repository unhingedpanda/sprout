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
    }

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

struct ServerState: Sendable {
    var downloadSpeed: Int64 = 0
    var uploadSpeed: Int64 = 0
    var freeSpace: Int64 = 0
    var connection = ""

    init() {}

    init(fields: [String: JSON]) {
        downloadSpeed = fields.int("dl_info_speed")
        uploadSpeed = fields.int("up_info_speed")
        freeSpace = fields.int("free_space_on_disk")
        connection = fields.string("connection_status")
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
    let priority: FilePriority

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
        return URL(string: url)?.host() ?? url
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

    init(id: String, fields: [String: JSON]) {
        self.id = id
        client = fields.string("client")
        progress = fields.double("progress")
        downloadSpeed = fields.int("dl_speed")
        uploadSpeed = fields.int("up_speed")
        countryCode = fields.string("country_code").uppercased()
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
