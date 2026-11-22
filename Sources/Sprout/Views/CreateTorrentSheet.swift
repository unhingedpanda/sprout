import SwiftUI

/// Makes a .torrent file from a file or folder, with the engine's torrent creator.
struct CreateTorrentSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var source: URL?
    @State private var trackers = ""
    @State private var webSeeds = ""
    @State private var comment = ""
    @State private var isPrivate = false
    @State private var pieceSize = 0
    @State private var format = "hybrid"
    @State private var startSeeding = true

    @State private var phase = Phase.editing
    @State private var progress = 0.0
    /// The running create-and-follow work, so Cancel and closing the sheet stop it.
    @State private var work: Task<Void, Never>?

    enum Phase: Equatable {
        case editing
        case creating(taskID: String, output: URL)
        case finished(URL)
        case failed(String)
    }

    private static let pieceSizes: [(label: String, bytes: Int)] =
        [("Automatic", 0)] + (0...7).map { step in
            let kib = 256 << step
            return (kib >= 1024 ? "\(kib / 1024) MB" : "\(kib) KB", kib * 1024)
        }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: "Create Torrent")
            switch phase {
            case .editing: form
            case .creating: creating
            case .finished(let url): finished(url)
            case .failed(let message): failed(message)
            }
        }
        .sproutSheet(width: 500)
        .toolbar { buttons }
        .onDisappear { cancel() }
    }

    // MARK: Editing

    private var form: some View {
        Form {
            Section {
                LabeledContent("Share") {
                    HStack {
                        Text(source?.lastPathComponent ?? "Nothing chosen")
                            .foregroundStyle(source == nil ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(source?.path ?? "")
                        Button("Choose…", action: chooseSource)
                    }
                }
            } footer: {
                Text("A single file, or a folder and everything in it. Hidden files are left out.")
            }

            Section {
                LinesEditor(text: $trackers, placeholder: "udp://tracker.example.org:1337/announce", minHeight: 48)
                    .accessibilityLabel("Trackers")
            } header: {
                Text("Trackers")
            } footer: {
                Text("One per line. A blank line starts a new tier, tried only when the ones above fail.")
            }

            Section {
                LinesEditor(text: $webSeeds, placeholder: "https://example.org/files/", minHeight: 22)
                    .accessibilityLabel("Web seeds")
            } header: {
                Text("Web seeds")
            } footer: {
                Text("Optional. Web servers that host the same files, one per line.")
            }

            Section {
                TextField("Comment", text: $comment, prompt: Text("Optional"))
                Picker("Piece size", selection: $pieceSize) {
                    ForEach(Self.pieceSizes, id: \.bytes) { Text($0.label).tag($0.bytes) }
                }
                Picker("Format", selection: $format) {
                    Text("v1 and v2").tag("hybrid")
                    Text("v1 only, for older apps").tag("v1")
                    Text("v2 only").tag("v2")
                }
                Toggle("Private torrent", isOn: $isPrivate)
                Toggle("Start seeding it now", isOn: $startSeeding)
            } footer: {
                if isPrivate {
                    Text("Peers come only from the trackers above: no DHT, peer exchange or local discovery.")
                }
            }
        }
        .sheetForm()
    }

    // MARK: Progress and result

    private var creating: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(source?.lastPathComponent ?? "")
                .font(.headline)
                .lineLimit(2)
            HStack(alignment: .bottom, spacing: 10) {
                DotText(text: String(Int(progress)), dot: 6, color: .lit)
                Text("%").font(.title3).foregroundStyle(.secondary)
            }
            Text("Reading every piece to fingerprint it. Large folders take a while.")
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Creating torrent, \(Int(progress)) percent")
    }

    private func finished(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Torrent created", systemImage: "checkmark.circle")
                .font(.headline)
            Text(startSeeding
                 ? "Saved as \(url.lastPathComponent). Sprout is seeding it, so share the file or its magnet link."
                 : "Saved as \(url.lastPathComponent).")
                .foregroundStyle(.secondary)
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                .buttonStyle(.inkLink)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func failed(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Couldn't create the torrent", systemImage: "exclamationmark.triangle")
                .font(.headline)
                .foregroundStyle(Color.fault)
            Text(message).foregroundStyle(.secondary).textSelection(.enabled)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The sheet's buttons for each phase, in the places macOS puts sheet buttons.
    @ToolbarContentBuilder
    private var buttons: some ToolbarContent {
        switch phase {
        case .editing:
            ToolbarItem(placement: .cancellationAction) { Button("Cancel", role: .cancel) { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create…", action: create)
                    .tint(.action)
                    .disabled(source == nil || work != nil)
            }
        case .creating:
            ToolbarItem(placement: .cancellationAction) { Button("Cancel", role: .cancel) { cancel() } }
        case .finished:
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.tint(.action) }
        case .failed:
            ToolbarItem(placement: .cancellationAction) { Button("Back") { phase = .editing } }
            ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() }.tint(.action) }
        }
    }

    // MARK: Work

    private func chooseSource() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK { source = panel.url }
    }

    private static func lines(_ text: String) -> [String] {
        text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private func create() {
        guard let source, let api = model.engine.api else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(source.lastPathComponent).torrent"
        panel.directoryURL = source.deletingLastPathComponent()
        panel.allowedContentTypes = [.init(filenameExtension: "torrent") ?? .data]
        guard panel.runModal() == .OK, let output = panel.url else { return }

        // Blank lines separate tracker tiers; web seeds ignore them.
        var trackerLines = Self.lines(trackers)
        while trackerLines.last == "" { trackerLines.removeLast() }
        var form = [
            "sourcePath": source.path,
            "torrentFilePath": output.path,
            "private": String(isPrivate),
            "format": format,
            "startSeeding": String(startSeeding),
            "comment": comment,
            "trackers": WebAPI.urlList(trackerLines),
            "urlSeeds": WebAPI.urlList(Self.lines(webSeeds).filter { !$0.isEmpty }),
        ]
        if pieceSize > 0 { form["pieceSize"] = String(pieceSize) }

        progress = 0
        work = Task {
            defer { work = nil }
            do {
                let reply = try JSON.decode(try await api.call("torrentcreator/addTask", form))
                guard let id = reply["taskID"]?.string else { throw CreatorError("The engine didn't start the task.") }
                // Cancelled while the engine was starting it: remove the task it just made.
                guard !Task.isCancelled else {
                    _ = try? await api.call("torrentcreator/deleteTask", ["taskID": id])
                    return
                }
                phase = .creating(taskID: id, output: output)
                try await follow(id, output: output, api: api)
            } catch {
                // After Cancel, a status request for the deleted task fails; that isn't a failure to show.
                if !Task.isCancelled { phase = .failed(error.localizedDescription) }
            }
        }
    }

    private func follow(_ id: String, output: URL, api: WebAPI) async throws {
        while !Task.isCancelled {
            let tasks = try JSON.decode(try await api.fetch("torrentcreator/status", ["taskID": id])).array ?? []
            guard let task = tasks.first else { throw CreatorError("The engine lost the task.") }
            switch task["status"]?.string {
            case "Finished":
                _ = try? await api.call("torrentcreator/deleteTask", ["taskID": id])
                phase = .finished(output)
                return
            case "Failed":
                _ = try? await api.call("torrentcreator/deleteTask", ["taskID": id])
                throw CreatorError(task["errorMessage"]?.string ?? "The engine gave no reason.")
            default:
                progress = task["progress"]?.double ?? progress
            }
            try await Task.sleep(for: .milliseconds(400))
        }
    }

    private func cancel() {
        work?.cancel()
        work = nil
        if case .creating(let id, _) = phase, let api = model.engine.api {
            Task { _ = try? await api.call("torrentcreator/deleteTask", ["taskID": id]) }
        }
        if case .creating = phase { phase = .editing }
    }
}

private struct CreatorError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
