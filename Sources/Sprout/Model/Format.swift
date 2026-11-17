import Foundation

enum Format {
    static func bytes(_ value: Int64) -> String {
        value.formatted(.byteCount(style: .file, spellsOutZero: false))
    }

    /// Below this, traffic is protocol chatter (keep-alives, requests), not a transfer.
    static let movingThreshold: Int64 = 1_000

    /// Speeds under the moving threshold render empty so idle rows stay quiet.
    static func speed(_ value: Int64) -> String {
        value >= movingThreshold ? "\(bytes(value))/s" : ""
    }

    /// A speed split into a dot-matrix number and its unit, e.g. ("24.6", "MB/s"). Zero reads "0".
    static func speedParts(_ value: Int64) -> (number: String, unit: String) {
        guard value > 0 else { return ("0", "B/s") }
        let units = ["B/s", "kB/s", "MB/s", "GB/s"]
        var amount = Double(value)
        var index = 0
        while amount >= 1000 && index < units.count - 1 {
            amount /= 1000
            index += 1
        }
        let number = amount >= 100 || index == 0 ? String(Int(amount.rounded())) : String(format: "%.1f", amount)
        return (number, units[index])
    }

    /// Whole percent, rounded down, without the sign (for dot-matrix figures).
    static func percentDigits(_ value: Double) -> String {
        String(Int((value * 100).rounded(.down)))
    }

    /// Rounds down, so 100% only appears once every piece is in.
    static func percent(_ value: Double) -> String {
        ((value * 100).rounded(.down) / 100).formatted(.percent.precision(.fractionLength(0)))
    }

    static func eta(_ torrent: Torrent) -> String {
        guard torrent.hasKnownETA else { return "" }
        let units: Set<Duration.UnitsFormatStyle.Unit> = torrent.eta < 60 ? [.seconds] : [.days, .hours, .minutes]
        return Duration.seconds(torrent.eta).formatted(.units(allowed: units, width: .abbreviated, maximumUnitCount: 2))
    }

    static func duration(seconds: Int64) -> String {
        guard seconds > 0 else { return "None" }
        return Duration.seconds(seconds).formatted(
            .units(allowed: [.days, .hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 2)
        )
    }

    /// qBittorrent caps ratio at 9999 to mean "infinite".
    static func ratio(_ value: Double) -> String {
        value >= 9999 ? "∞" : value.formatted(.number.precision(.fractionLength(2)))
    }

    static func date(_ value: Date?) -> String {
        guard let value, value.timeIntervalSince1970 > 0 else { return "Not yet" }
        return value.formatted(date: .abbreviated, time: .shortened)
    }
}
