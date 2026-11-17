import Foundation

/// Client for qBittorrent's Web API v2, authenticated with the engine's API key.
struct WebAPI: Sendable {
    let baseURL: URL
    let apiKey: String

    struct HTTPError: LocalizedError {
        let status: Int
        let body: String
        var errorDescription: String? {
            body.isEmpty ? "The engine answered with HTTP \(status)." : body
        }
    }

    // MARK: Reads

    func version() async throws -> String {
        String(decoding: try await get("app/version"), as: UTF8.self)
    }

    func mainData(rid: Int) async throws -> JSON {
        try JSON.decode(try await get("sync/maindata", ["rid": String(rid)]))
    }

    func properties(hash: String) async throws -> JSON {
        try JSON.decode(try await get("torrents/properties", ["hash": hash]))
    }

    func files(hash: String) async throws -> [TorrentFile] {
        let json = try JSON.decode(try await get("torrents/files", ["hash": hash]))
        return (json.array ?? []).compactMap { $0.object.map(TorrentFile.init) }
    }

    func trackers(hash: String) async throws -> [Tracker] {
        let json = try JSON.decode(try await get("torrents/trackers", ["hash": hash]))
        return (json.array ?? []).compactMap { $0.object.map(Tracker.init) }
    }

    func peers(hash: String) async throws -> [Peer] {
        let json = try JSON.decode(try await get("sync/torrentPeers", ["hash": hash, "rid": "0"]))
        return (json["peers"]?.object ?? [:]).map { Peer(id: $0.key, fields: $0.value.object ?? [:]) }
    }

    /// One value per piece: 0 missing, 1 downloading, 2 downloaded.
    func pieceStates(hash: String) async throws -> [Int] {
        let json = try JSON.decode(try await get("torrents/pieceStates", ["hash": hash]))
        return (json.array ?? []).map { Int($0.double ?? 0) }
    }

    func defaultSavePath() async throws -> String {
        String(decoding: try await get("app/defaultSavePath"), as: UTF8.self)
    }

    // MARK: Actions

    func add(urls: [String], options: AddOptions) async throws {
        var form = options.fields
        form["urls"] = urls.joined(separator: "\n")
        // Links have no file list yet: stop once it arrives so files can be chosen first.
        if options.chooseFilesFirst {
            form["stopped"] = "false"
            form["stopCondition"] = "MetadataReceived"
        }
        try await post("torrents/add", form)
    }

    func add(torrentFiles: [URL], options: AddOptions) async throws {
        var fields = options.fields
        if options.chooseFilesFirst { fields["stopped"] = "true" }
        var parts: [Multipart.File] = []
        for url in torrentFiles {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            parts.append(.init(field: "torrents", filename: url.lastPathComponent, data: try Data(contentsOf: url)))
        }
        try await postMultipart("torrents/add", fields: fields, files: parts)
    }

    func start(_ hashes: Set<String>) async throws {
        try await post("torrents/start", ["hashes": hashes.joined(separator: "|")])
    }

    func stop(_ hashes: Set<String>) async throws {
        try await post("torrents/stop", ["hashes": hashes.joined(separator: "|")])
    }

    func delete(_ hashes: Set<String>, deleteFiles: Bool) async throws {
        try await post("torrents/delete", ["hashes": hashes.joined(separator: "|"), "deleteFiles": String(deleteFiles)])
    }

    func setFilePriority(hash: String, fileIndexes: [Int], priority: FilePriority) async throws {
        try await post("torrents/filePrio", [
            "hash": hash,
            "id": fileIndexes.map(String.init).joined(separator: "|"),
            "priority": String(priority.rawValue),
        ])
    }

    func shutdown() async throws {
        try await post("app/shutdown", [:])
    }

    /// Calls a torrents/* action on several torrents, e.g. "recheck", "reannounce", "topPrio".
    func torrents(_ action: String, _ hashes: Set<String>, _ extra: [String: String] = [:]) async throws {
        try await post("torrents/\(action)", extra.merging(["hashes": hashes.joined(separator: "|")]) { $1 })
    }

    func rename(hash: String, to name: String) async throws {
        try await post("torrents/rename", ["hash": hash, "name": name])
    }

    func createCategory(_ name: String) async throws {
        try await post("torrents/createCategory", ["category": name, "savePath": ""])
    }

    func createTags(_ tags: [String]) async throws {
        try await post("torrents/createTags", ["tags": tags.joined(separator: ",")])
    }

    func toggleAlternativeSpeeds() async throws {
        try await post("transfer/toggleSpeedLimitsMode", [:])
    }

    // MARK: Preferences

    func preferences() async throws -> [String: JSON] {
        try JSON.decode(try await get("app/preferences")).object ?? [:]
    }

    func setPreferences(_ changes: [String: JSON]) async throws {
        let data = try JSONSerialization.data(withJSONObject: changes.mapValues(\.foundationValue))
        try await post("app/setPreferences", ["json": String(decoding: data, as: UTF8.self)])
    }

    // MARK: Transport

    private func request(_ path: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: "api/v2/\(path)"))
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        return request
    }

    private func get(_ path: String, _ query: [String: String] = [:]) async throws -> Data {
        var request = request(path)
        if !query.isEmpty, let url = request.url {
            request.url = url.appending(queryItems: query.map { URLQueryItem(name: $0.key, value: $0.value) })
        }
        return try await send(request)
    }

    @discardableResult
    private func post(_ path: String, _ form: [String: String]) async throws -> Data {
        var request = request(path)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        // URLComponents leaves "+" alone, which a form body would read as a space.
        request.httpBody = Data((components.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
        return try await send(request)
    }

    private func postMultipart(_ path: String, fields: [String: String], files: [Multipart.File]) async throws {
        var request = request(path)
        request.httpMethod = "POST"
        let body = Multipart(fields: fields, files: files)
        request.setValue("multipart/form-data; boundary=\(body.boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data
        try await send(request)
    }

    @discardableResult
    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw HTTPError(status: status, body: String(decoding: data, as: UTF8.self))
        }
        return data
    }
}

private struct Multipart {
    struct File {
        let field: String
        let filename: String
        let data: Data
    }

    let boundary = "sprout-\(UUID().uuidString)"
    let data: Data

    init(fields: [String: String], files: [File]) {
        var body = Data()
        func line(_ text: String) { body.append(Data((text + "\r\n").utf8)) }
        for (name, value) in fields {
            line("--\(boundary)")
            line("Content-Disposition: form-data; name=\"\(name)\"")
            line("")
            line(value)
        }
        for file in files {
            line("--\(boundary)")
            line("Content-Disposition: form-data; name=\"\(file.field)\"; filename=\"\(file.filename.replacingOccurrences(of: "\"", with: "%22"))\"")
            line("Content-Type: application/x-bittorrent")
            line("")
            body.append(file.data)
            line("")
        }
        line("--\(boundary)--")
        data = body
    }
}

struct AddOptions: Sendable {
    var savePath: String?
    var category = ""
    var startNow = true
    /// Add without downloading, so files can be picked in the inspector before starting.
    var chooseFilesFirst = false

    var fields: [String: String] {
        var form = ["stopped": String(!startNow)]
        if let savePath { form["savepath"] = savePath }
        if !category.isEmpty { form["category"] = category }
        return form
    }
}
