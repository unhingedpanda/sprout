import Foundation
import Observation

/// Starts, watches and stops the bundled qbittorrent-nox engine.
///
/// The engine gets its own profile under Application Support, listens only on
/// 127.0.0.1 on a free port, and accepts requests only with a random API key that
/// Sprout writes into the engine's config. Localhost authentication stays on, so other
/// programs on the Mac cannot drive the engine without that key.
@MainActor @Observable
final class EngineController {
    enum Status {
        case stopped
        case starting
        case running(WebAPI)
        case failed(String)
    }

    private(set) var status: Status = .stopped
    private var process: Process?

    static let profileURL = URL.applicationSupportDirectory.appending(path: "Sprout/Engine", directoryHint: .isDirectory)
    static var logURL: URL { profileURL.appending(path: "engine.log") }
    private static var configURL: URL { profileURL.appending(path: "qBittorrent/config/qBittorrent.ini") }
    /// The running engine's process ID, so a launch after a crash can stop the engine left behind.
    private static var pidURL: URL { profileURL.appending(path: "engine.pid") }

    var api: WebAPI? {
        if case .running(let api) = status { api } else { nil }
    }

    func start() async {
        if case .starting = status { return }
        if case .running = status { return }
        status = .starting
        do {
            status = .running(try await launch())
        } catch {
            process?.terminate()
            process = nil
            status = .failed(error.localizedDescription)
        }
    }

    /// Asks the engine to save resume data and exit; terminates it if it takes too long.
    func stop() async {
        guard let process else { return }
        if let api { try? await api.shutdown() }
        for _ in 0..<100 where process.isRunning {
            try? await Task.sleep(for: .milliseconds(100))
        }
        if process.isRunning { process.terminate() }
        self.process = nil
        try? FileManager.default.removeItem(at: Self.pidURL)
        status = .stopped
    }

    // MARK: Launch

    private struct LaunchError: LocalizedError {
        let errorDescription: String?
    }

    private func launch() async throws -> WebAPI {
        let binary = try Self.engineBinary()
        await Self.stopLeftoverEngine()
        guard let port = Self.freeLoopbackPort() else {
            throw LaunchError(errorDescription: "Sprout couldn't find a free local port for the engine.")
        }
        let apiKey = try Self.prepareConfig(port: port)

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: Self.profileURL, withIntermediateDirectories: true)
        fileManager.createFile(atPath: Self.logURL.path, contents: nil)
        let log = try FileHandle(forWritingTo: Self.logURL)

        let process = Process()
        process.executableURL = binary
        process.arguments = ["--profile=\(Self.profileURL.path)", "--confirm-legal-notice"]
        process.standardOutput = log
        process.standardError = log
        process.terminationHandler = { [weak self] finished in
            let code = finished.terminationStatus
            Task { @MainActor in self?.engineExited(code: code) }
        }
        try process.run()
        self.process = process
        try? String(process.processIdentifier).write(to: Self.pidURL, atomically: true, encoding: .utf8)

        let api = WebAPI(baseURL: URL(string: "http://127.0.0.1:\(port)/")!, apiKey: apiKey)
        for _ in 0..<150 {
            guard process.isRunning else { break }
            if (try? await api.version()) != nil { return api }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw LaunchError(errorDescription: "The engine didn't start. \(Self.logTail())")
    }

    private func engineExited(code: Int32) {
        process = nil
        try? FileManager.default.removeItem(at: Self.pidURL)
        if case .running = status {
            status = .failed("The engine stopped unexpectedly (exit code \(code)). \(Self.logTail())")
        }
    }

    /// If Sprout crashed, its engine may still be running and holding the profile, which would
    /// make this launch fail. Ask that engine to save and quit, and force it only if it won't.
    private static func stopLeftoverEngine() async {
        guard let text = try? String(contentsOf: pidURL, encoding: .utf8),
              let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        defer { try? FileManager.default.removeItem(at: pidURL) }
        guard isEngine(pid) else { return }

        let ini = IniFile((try? String(contentsOf: configURL, encoding: .utf8)) ?? "")
        if let port = ini.value(section: "WebUI", key: "Port"), let key = ini.value(section: "WebUI", key: "APIKey"),
           let url = URL(string: "http://127.0.0.1:\(port)/") {
            try? await WebAPI(baseURL: url, apiKey: key).shutdown()
        }
        for signal in [0, SIGTERM, SIGKILL] {
            if signal != 0 { kill(pid, signal) }
            for _ in 0..<100 where isEngine(pid) {
                try? await Task.sleep(for: .milliseconds(100))
            }
            if !isEngine(pid) { return }
        }
    }

    /// True while `pid` is alive and is a qbittorrent-nox process, so a reused PID is never touched.
    private static func isEngine(_ pid: pid_t) -> Bool {
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return false }
        let path = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return URL(filePath: path).lastPathComponent == "qbittorrent-nox"
    }

    private static func engineBinary() throws -> URL {
        if let override = ProcessInfo.processInfo.environment["SPROUT_ENGINE"] {
            return URL(filePath: override)
        }
        let url = Bundle.main.bundleURL.appending(path: "Contents/Helpers/qbittorrent-nox.app/Contents/MacOS/qbittorrent-nox")
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            throw LaunchError(errorDescription: "The engine is missing from the app bundle.")
        }
        return url
    }

    /// Writes the WebUI settings Sprout depends on and returns the API key.
    /// Other settings in the file belong to the engine and are left alone.
    private static func prepareConfig(port: UInt16) throws -> String {
        let url = configURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var ini = IniFile((try? String(contentsOf: url, encoding: .utf8)) ?? "")

        // qBittorrent 5.x reads these from the [WebUI] section (Preferences "WebUI/…" keys).
        var apiKey = ini.value(section: "WebUI", key: "APIKey") ?? ""
        if !isValidAPIKey(apiKey) { apiKey = makeAPIKey() }

        ini.set(section: "LegalNotice", key: "Accepted", value: "true")
        ini.set(section: "WebUI", key: "Enabled", value: "true")
        ini.set(section: "WebUI", key: "Address", value: "127.0.0.1")
        ini.set(section: "WebUI", key: "Port", value: String(port))
        ini.set(section: "WebUI", key: "APIKey", value: apiKey)
        ini.set(section: "WebUI", key: "LocalHostAuth", value: "true")
        try ini.text.write(to: url, atomically: true, encoding: .utf8)
        return apiKey
    }

    // qBittorrent accepts "qbt_" followed by 28 characters (Utils::APIKey::isValid).
    private static func isValidAPIKey(_ key: String) -> Bool {
        key.hasPrefix("qbt_") && key.count == 32
    }

    private static func makeAPIKey() -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        var generator = SystemRandomNumberGenerator()
        return "qbt_" + String((0..<28).map { _ in alphabet.randomElement(using: &generator)! })
    }

    private static func freeLoopbackPort() -> UInt16? {
        let socketFD = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else { return nil }
        defer { close(socketFD) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketFD, $0, length) == 0 && getsockname(socketFD, $0, &length) == 0
            }
        }
        return bound ? UInt16(bigEndian: address.sin_port) : nil
    }

    static func logTail(lines: Int = 6) -> String {
        guard let text = try? String(contentsOf: logURL, encoding: .utf8) else { return "" }
        let meaningful = text.split(separator: "\n").filter { !$0.hasPrefix("qt.network.ssl") }
        return meaningful.suffix(lines).joined(separator: "\n")
    }
}

/// Minimal editor for the engine's INI file: reads and replaces single keys, keeps everything else.
struct IniFile {
    private var lines: [String]

    init(_ text: String) {
        lines = text.isEmpty ? [] : text.components(separatedBy: "\n")
    }

    var text: String { lines.joined(separator: "\n") }

    func value(section: String, key: String) -> String? {
        guard let index = keyIndex(section: section, key: key) else { return nil }
        return String(lines[index].dropFirst(key.count + 1))
    }

    mutating func set(section: String, key: String, value: String) {
        let line = "\(key)=\(value)"
        if let index = keyIndex(section: section, key: key) {
            lines[index] = line
        } else if let header = lines.firstIndex(of: "[\(section)]") {
            lines.insert(line, at: header + 1)
        } else {
            if let last = lines.last, !last.isEmpty { lines.append("") }
            lines.append(contentsOf: ["[\(section)]", line])
        }
    }

    private func keyIndex(section: String, key: String) -> Int? {
        var inSection = false
        for (index, line) in lines.enumerated() {
            if line.hasPrefix("[") {
                inSection = line == "[\(section)]"
            } else if inSection, line.hasPrefix("\(key)=") {
                return index
            }
        }
        return nil
    }
}
