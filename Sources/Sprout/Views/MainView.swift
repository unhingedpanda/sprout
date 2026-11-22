import SwiftUI

struct MainView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var searchFocused: Bool

    var body: some View {
        @Bindable var model = model

        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 260)
        } detail: {
            TorrentList()
                // Room for a name, the tray and the figure. With the sidebar and the inspector at its ideal width, this sets the 900 window minimum.
                .frame(minWidth: 360)
                .inspector(isPresented: $model.showsInspector) {
                    InspectorView()
                        .groundedInspector()
                        .inspectorColumnWidth(min: 280, ideal: 330, max: 460)
                }
        }
        .navigationTitle(model.sidebar.title)
        .navigationSubtitle(countSummary)
        .containerBackground(Color.ground, for: .window)
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "Filter by name")
        .searchFocused($searchFocused)
        .onChange(of: model.searchFocusRequests) { searchFocused = true }
        .toolbar { toolbar }
        .dropDestination(for: URL.self) { urls, _ in
            model.open(urls)
            return true
        }
        .modifier(MainDialogs())
        // After the dialogs, so sheets get ink controls too, not the system accent.
        .tint(.lit)
    }

    // Speeds live in the pulse band; the subtitle only counts, so nothing is said twice.
    private var countSummary: String {
        let count = model.visibleTorrents.count
        let total = model.count(model.sidebar)
        // While filtering, say how many of the list match, not that the list is empty.
        if count != total { return "\(count) of \(total) torrents" }
        return count == 1 ? "1 torrent" : "\(count) torrents"
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
            Toggle("Alternative Speeds", systemImage: "tortoise", isOn: Binding(
                get: { model.server.usesAlternativeSpeeds },
                set: { _ in model.toggleAlternativeSpeeds() }
            ))
            .help("Use the alternative speed limits set in Settings (⌥⌘L)")
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
        List(selection: Binding($model.sidebar)) {
            Section("Torrents") {
                ForEach(TorrentFilter.allCases) { row(.state($0)) }
            }
            if !model.categories.isEmpty {
                Section("Categories") {
                    ForEach(model.categories, id: \.self) { name in
                        row(.category(name)).contextMenu {
                            Button("Choose Folder…") { model.editingCategory = name }
                            Button("Remove Category…") { model.pendingCategoryRemoval = name }
                        }
                    }
                    row(.category(""))
                }
            }
            if !model.tags.isEmpty {
                Section("Tags") {
                    ForEach(model.tags, id: \.self) { name in
                        row(.tag(name)).contextMenu {
                            Button("Remove Tag") { model.removeTag(name) }
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func row(_ item: SidebarItem) -> some View {
        Label {
            Text(item.title)
        } icon: {
            Image(systemName: item.symbol).foregroundStyle(.secondary)
        }
        .badge(model.count(item))
        .tag(item)
    }
}

private extension Binding where Value == SidebarItem? {
    /// List selection wants an optional; the sidebar always has one item selected.
    init(_ source: Binding<SidebarItem>) {
        self.init(get: { source.wrappedValue }, set: { if let value = $0 { source.wrappedValue = value } })
    }
}

/// Sheet items: SwiftUI wants Identifiable values.
private struct HashSet: Identifiable {
    let hashes: Set<String>
    var id: Set<String> { hashes }
}

private struct CategoryName: Identifiable {
    let name: String
    var id: String { name }
}

/// The main window's sheet, dialogs, prompts and folder picker.
private struct MainDialogs: ViewModifier {
    @Environment(AppModel.self) private var model
    @State private var promptText = ""
    @State private var moving: Set<String> = []

    func body(content: Content) -> some View {
        @Bindable var model = model
        content
            .sheet(isPresented: $model.showsAddSheet) { AddTorrentSheet() }
            .sheet(isPresented: $model.showsCreateSheet) { CreateTorrentSheet() }
            .sheet(item: Binding(get: { model.pendingLimits.map(HashSet.init) }, set: { model.pendingLimits = $0?.hashes })) {
                LimitsSheet(hashes: $0.hashes)
            }
            .sheet(item: Binding(get: { model.editingCategory.map(CategoryName.init) }, set: { model.editingCategory = $0?.name })) {
                CategorySheet(category: $0.name)
            }
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
                model.prompt?.title ?? "",
                isPresented: Binding(get: { model.prompt != nil }, set: { if !$0 { model.prompt = nil } }),
                presenting: model.prompt
            ) { prompt in
                TextField("Name", text: $promptText)
                Button(prompt.action) { model.answer(prompt, with: promptText) }
                Button("Cancel", role: .cancel) {}
            }
            .onChange(of: model.prompt?.id) { promptText = model.prompt?.initial ?? "" }
            .background { moveFolderPicker }
            .confirmationDialog(
                "Remove the category “\(model.pendingCategoryRemoval ?? "")”?",
                isPresented: Binding(get: { model.pendingCategoryRemoval != nil }, set: { if !$0 { model.pendingCategoryRemoval = nil } }),
                presenting: model.pendingCategoryRemoval
            ) { name in
                Button("Remove Category", role: .destructive) { model.removeCategory(name) }
            } message: { name in
                Text(categoryRemovalMessage(name))
            }
            .alert(
                "Sprout couldn't complete that",
                isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
            ) {} message: {
                Text(model.errorMessage ?? "")
            }
    }

    private func categoryRemovalMessage(_ name: String) -> String {
        let count = model.torrents.values.count { $0.category == name || $0.category.hasPrefix(name + "/") }
        let subcategories = model.categories.filter { $0.hasPrefix(name + "/") }
        let only = model.torrents.values.first { $0.category == name }
        var text = switch count {
        case 0: "No torrents use it."
        case 1: "“\(only?.name ?? name)” loses the category. If it uses the category folder, it moves to the default folder."
        default: "\(count) torrents lose the category. Any that use the category folder move to the default folder."
        }
        if !subcategories.isEmpty { text += " Its subcategories are removed too: \(subcategories.joined(separator: ", "))." }
        return text
    }

    private var removalTitle: String {
        let count = model.pendingRemoval?.count ?? 0
        if count == 1, let hash = model.pendingRemoval?.first, let name = model.torrents[hash]?.name {
            return "Remove “\(name)”?"
        }
        return "Remove \(count) torrents?"
    }

    /// "Move Files…" asks for a folder. Kept on its own view so the button label only applies here.
    private var moveFolderPicker: some View {
        Color.clear
            .fileImporter(
                isPresented: Binding(get: { model.pendingMove != nil }, set: {
                    if !$0, let hashes = model.pendingMove { moving = hashes; model.pendingMove = nil }
                }),
                allowedContentTypes: [.folder]
            ) { result in
                let hashes = model.pendingMove ?? moving
                if case .success(let folder) = result, !hashes.isEmpty { model.move(hashes, to: folder) }
                model.pendingMove = nil
            }
            .fileDialogConfirmationLabel("Move Here")
    }
}
