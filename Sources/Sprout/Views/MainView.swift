import SwiftUI

struct MainView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 260)
        } detail: {
            TorrentList()
                .inspector(isPresented: $model.showsInspector) {
                    InspectorView()
                        .groundedInspector()
                        .inspectorColumnWidth(min: 280, ideal: 330, max: 460)
                }
        }
        .navigationTitle(model.filter.title)
        .navigationSubtitle(countSummary)
        .containerBackground(Color.ground, for: .window)
        .tint(.lit)
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "Filter by name")
        .toolbar { toolbar }
        .dropDestination(for: URL.self) { urls, _ in
            model.open(urls)
            return true
        }
        .sheet(isPresented: $model.showsAddSheet) { AddTorrentSheet() }
        .confirmationDialog(
            removalTitle,
            isPresented: Binding(get: { model.pendingRemoval != nil }, set: { if !$0 { model.pendingRemoval = nil } }),
            presenting: model.pendingRemoval
        ) { hashes in
            Button("Remove") { model.remove(hashes, deleteFiles: false) }
                .keyboardShortcut(.defaultAction)
            Button("Remove and Delete Files", role: .destructive) { model.remove(hashes, deleteFiles: true) }
        } message: { _ in
            Text("Removing a torrent keeps its downloaded files unless you also delete them.")
        }
        .alert(
            "Sprout couldn't complete that",
            isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
        ) {} message: {
            Text(model.errorMessage ?? "")
        }
    }

    // Speeds live in the pulse band; the subtitle only counts, so nothing is said twice.
    private var countSummary: String {
        let count = model.visibleTorrents.count
        return count == 1 ? "1 torrent" : "\(count) torrents"
    }

    private var removalTitle: String {
        let count = model.pendingRemoval?.count ?? 0
        if count == 1, let hash = model.pendingRemoval?.first, let name = model.torrents[hash]?.name {
            return "Remove “\(name)”?"
        }
        return "Remove \(count) torrents?"
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button("Add Torrent", systemImage: "plus") { model.showsAddSheet = true }
                .help("Add a magnet link or .torrent file (⌘O)")
        }
        ToolbarItemGroup {
            Button("Start", systemImage: "play.fill") { model.startSelected() }
                .disabled(!model.canStart)
                .help("Start the selected torrents")
            Button("Stop", systemImage: "stop.fill") { model.stopSelected() }
                .disabled(!model.canStop)
                .help("Stop the selected torrents")
        }
        ToolbarItem {
            Button("Remove", systemImage: "trash") { model.requestRemoveSelected() }
                .disabled(model.selection.isEmpty)
                .help("Remove the selected torrents")
        }
        ToolbarItem {
            @Bindable var model = model
            Menu("Sort", systemImage: "arrow.up.arrow.down") {
                Picker("Sort By", selection: $model.sortKey) {
                    ForEach(SortKey.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
                Divider()
                Picker("Order", selection: $model.sortAscending) {
                    Text("Ascending").tag(true)
                    Text("Descending").tag(false)
                }
                .pickerStyle(.inline)
            }
            .help("Sort torrents")
        }
        ToolbarItem {
            @Bindable var model = model
            Toggle("Inspector", systemImage: "sidebar.trailing", isOn: $model.showsInspector)
                .help("Show or hide the inspector (⌥⌘I)")
        }
    }
}

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: Binding($model.filter)) {
            Section("Torrents") {
                ForEach(TorrentFilter.allCases) { filter in
                    Label {
                        Text(filter.title)
                    } icon: {
                        Image(systemName: filter.symbol).foregroundStyle(.secondary)
                    }
                    .badge(model.count(filter))
                    .tag(filter)
                }
            }
        }
        .scrollContentBackground(.hidden)
    }
}

private extension Binding where Value == TorrentFilter? {
    /// List selection wants an optional; the sidebar always has one filter selected.
    init(_ source: Binding<TorrentFilter>) {
        self.init(get: { source.wrappedValue }, set: { if let value = $0 { source.wrappedValue = value } })
    }
}
