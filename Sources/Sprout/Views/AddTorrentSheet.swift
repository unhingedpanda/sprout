import SwiftUI
import UniformTypeIdentifiers

struct AddTorrentSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var links = ""
    @State private var files: [URL] = []
    @State private var savePath = ""
    @State private var startNow = true
    @State private var chooseFilesFirst = false
    @State private var category = ""
    @State private var choosingFiles = false
    @State private var choosingFolder = false
    @State private var freeSpace: Int64?
    /// The engine's default folder. A torrent added without a folder can follow its category's folder.
    @State private var defaultPath = ""

    private static let torrentType = UTType(filenameExtension: "torrent") ?? .data

    private var linkList: [String] {
        links.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: "Add Torrent")
            Form {
                Section {
                    LinesEditor(text: $links, placeholder: "Paste magnet links or .torrent URLs")
                        .accessibilityLabel("Magnet links or URLs")
                } header: {
                    Text("Links")
                } footer: {
                    Text("One link per line.")
                }

                Section("Files") {
                    ForEach(files, id: \.self) { url in
                        HStack {
                            Label(url.lastPathComponent, systemImage: "doc")
                            Spacer()
                            Button("Remove \(url.lastPathComponent)", systemImage: "minus.circle") {
                                files.removeAll { $0 == url }
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .help("Don't add this file")
                        }
                    }
                    Button("Choose .torrent Files…") { choosingFiles = true }
                        .fileImporter(isPresented: $choosingFiles, allowedContentTypes: [Self.torrentType], allowsMultipleSelection: true) { result in
                            if case .success(let urls) = result { files.append(contentsOf: urls) }
                        }
                }

                Section {
                    LabeledContent {
                        HStack {
                            Text(savePath.isEmpty ? "Default folder" : URL(filePath: savePath).lastPathComponent)
                                .help(savePath)
                            Button("Change…") { choosingFolder = true }
                                .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
                                    if case .success(let url) = result { savePath = url.path }
                                }
                        }
                    } label: {
                        Text("Save to")
                        if let freeSpace {
                            Text("\(Format.bytes(freeSpace)) free").monospacedDigit()
                        }
                    }
                    if !model.categories.isEmpty {
                        Picker("Category", selection: $category) {
                            Text("None").tag("")
                            ForEach(model.categories, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    // Off while choosing files first: that torrent stops once its file list arrives.
                    Toggle("Start downloading right away", isOn: chooseFilesFirst ? .constant(false) : $startNow)
                        .disabled(chooseFilesFirst)
                    Toggle("Choose files before downloading", isOn: $chooseFilesFirst)
                } header: {
                    Text("Options")
                } footer: {
                    if chooseFilesFirst {
                        Text("Sprout waits for the file list, then stops the torrent. Pick files in the inspector and press Start.")
                    }
                }
            }
            .sheetForm()
        }
        .sproutSheet(width: 480)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel", role: .cancel) { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") { add() }
                    .tint(.action)
                    .disabled(linkList.isEmpty && files.isEmpty)
            }
        }
        .task {
            if savePath.isEmpty, let path = try? await model.engine.api?.defaultSavePath() {
                defaultPath = path
                savePath = path
            }
        }
        .task(id: savePath) {
            guard !savePath.isEmpty, let api = model.engine.api,
                  let data = try? await api.fetch("app/getFreeSpaceAtPath", ["path": savePath]) else { freeSpace = nil; return }
            freeSpace = Int64(String(decoding: data, as: UTF8.self))
        }
    }

    private func add() {
        let options = AddOptions(
            // Sending a folder turns off "Use Category Folder"; send one only when the user chose it.
            savePath: savePath.isEmpty || savePath == defaultPath ? nil : savePath,
            category: category,
            startNow: startNow,
            chooseFilesFirst: chooseFilesFirst
        )
        if !linkList.isEmpty { model.add(links: linkList, options: options) }
        if !files.isEmpty { model.add(files: files, options: options) }
        dismiss()
    }
}
