import SwiftUI

/// The torrent actions, shared by the Torrent menu and the list's context menu.
struct TorrentActions: View {
    let model: AppModel
    let hashes: Set<String>
    var showsShortcuts = false

    private var torrents: [Torrent] { hashes.compactMap { model.torrents[$0] } }
    private var single: Torrent? { torrents.count == 1 ? torrents.first : nil }
    private var none: Bool { torrents.isEmpty }

    var body: some View {
        Button("Start") { model.start(hashes) }
            .shortcut("r", showsShortcuts)
            .disabled(!torrents.contains { $0.state.isStopped })
        Button("Stop") { model.stop(hashes) }
            .shortcut(".", showsShortcuts)
            .disabled(!torrents.contains { !$0.state.isStopped })
        Toggle("Force Start", isOn: Binding(
            get: { !none && torrents.allSatisfy(\.isForced) },
            set: { model.forceStart(hashes, $0) }
        ))
        .help("Start now, ignoring the queue limits")
        .disabled(none)

        Divider()

        Menu("Category") {
            Picker("Category", selection: Binding(
                get: { Set(torrents.map(\.category)).count == 1 ? torrents.first?.category : nil },
                set: { if let name = $0 { model.setCategory(name, on: hashes) } }
            )) {
                Text("None").tag(Optional(""))
                ForEach(model.categories, id: \.self) { Text($0).tag(Optional($0)) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            Divider()
            Button("New Category…") { model.prompt = TextPrompt(kind: .newCategory(hashes)) }
        }
        .disabled(none)
        Menu("Tags") {
            ForEach(model.tags, id: \.self) { tag in
                Toggle(tag, isOn: Binding(
                    get: { torrents.allSatisfy { $0.tags.contains(tag) } },
                    set: { model.setTag(tag, $0, on: hashes) }
                ))
            }
            if !model.tags.isEmpty { Divider() }
            Button("New Tag…") { model.prompt = TextPrompt(kind: .newTag(hashes)) }
        }
        .disabled(none)

        Divider()

        Toggle("Download in Order", isOn: Binding(
            get: { !none && torrents.allSatisfy(\.isSequential) },
            set: { _ in model.run("toggleSequentialDownload", on: hashes) }
        ))
        .help("Fetch pieces from start to end, so media can be previewed while it downloads")
        .disabled(none || torrents.allSatisfy { $0.progress >= 1 })
        if model.server.queueingEnabled {
            Menu("Queue") {
                Button("Move to Top") { model.run("topPrio", on: hashes) }
                Button("Move Up") { model.run("increasePrio", on: hashes) }
                Button("Move Down") { model.run("decreasePrio", on: hashes) }
                Button("Move to Bottom") { model.run("bottomPrio", on: hashes) }
            }
            .disabled(!torrents.contains { $0.queuePosition > 0 })
        }

        Divider()

        Button("Show in Finder") { if let single { model.revealInFinder(single) } }
            .shortcut("r", showsShortcuts, modifiers: [.command, .shift])
            .disabled(single == nil)
        Button("Move Files…") { model.pendingMove = hashes }
            .disabled(none)
        Button("Rename…") {
            if let single { model.prompt = TextPrompt(kind: .rename(single.id), initial: single.name) }
        }
        .disabled(single == nil)
        Button("Copy Info Hash") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(single?.id ?? "", forType: .string)
        }
        .disabled(single == nil)

        Divider()

        Button("Verify Local Data") { model.run("recheck", on: hashes) }
            .help("Check downloaded pieces against the torrent and fetch any that are damaged")
            .disabled(none)
        Button("Ask Trackers for More Peers") { model.run("reannounce", on: hashes) }
            .disabled(none || torrents.allSatisfy { $0.state.isStopped })

        Divider()

        Button("Remove…") { model.requestRemove(hashes) }
            .shortcut(.delete, showsShortcuts)
            .disabled(none)
    }
}

private extension View {
    /// Shortcuts belong to the menu bar copy; the context menu repeats them only as hints.
    @ViewBuilder
    func shortcut(_ key: KeyEquivalent, _ enabled: Bool, modifiers: EventModifiers = .command) -> some View {
        if enabled { keyboardShortcut(key, modifiers: modifiers) } else { self }
    }
}
