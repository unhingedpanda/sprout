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
            Form {
                Section {
                    TextField("Magnet links or URLs", text: $links, prompt: Text("Paste magnet links or .torrent URLs"), axis: .vertical)
                        .lineLimit(3...6)
                        .labelsHidden()
                        .multilineTextAlignment(.leading)
                } header: {
                    Text("Links")
                } footer: {
                    Text("One link per line.")
                }

                Section("Files") {
                    ForEach(files, id: \.self) { url in
                        Label(url.lastPathComponent, systemImage: "doc")
                    }
                    .onDelete { files.remove(atOffsets: $0) }
                    Button("Choose .torrent Files…") { choosingFiles = true }
                        .fileImporter(isPresented: $choosingFiles, allowedContentTypes: [Self.torrentType], allowsMultipleSelection: true) { result in
                            if case .success(let urls) = result { files.append(contentsOf: urls) }
                        }
                }

                Section {
                    LabeledContent("Save to") {
                        HStack {
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(savePath.isEmpty ? "Default folder" : URL(filePath: savePath).lastPathComponent)
                                    .help(savePath)
                                if let freeSpace {
                                    Text("\(Format.bytes(freeSpace)) free")
                                        .font(.caption)
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Button("Change…") { choosingFolder = true }
                                .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
                                    if case .success(let url) = result { savePath = url.path }
                                }
                        }
                    }
                    if !model.categories.isEmpty {
                        Picker("Category", selection: $category) {
                            Text("None").tag("")
                            ForEach(model.categories, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    Toggle("Start downloading right away", isOn: $startNow)
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
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") { add() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(linkList.isEmpty && files.isEmpty)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 480)
        .navigationTitle("Add Torrent")
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
