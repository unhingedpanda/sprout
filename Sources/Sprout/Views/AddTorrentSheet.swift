import SwiftUI
import UniformTypeIdentifiers

struct AddTorrentSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var links = ""
    @State private var files: [URL] = []
    @State private var savePath = ""
    @State private var startNow = true
    @State private var choosingFiles = false
    @State private var choosingFolder = false

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

                Section("Options") {
                    LabeledContent("Save to") {
                        HStack {
                            Text(savePath.isEmpty ? "Default folder" : URL(filePath: savePath).lastPathComponent)
                                .foregroundStyle(.secondary)
                                .help(savePath)
                            Button("Change…") { choosingFolder = true }
                                .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
                                    if case .success(let url) = result { savePath = url.path }
                                }
                        }
                    }
                    Toggle("Start downloading right away", isOn: $startNow)
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
            if savePath.isEmpty, let path = try? await model.engine.api?.defaultSavePath() { savePath = path }
        }
    }

    private func add() {
        let path = savePath.isEmpty ? nil : savePath
        if !linkList.isEmpty { model.add(links: linkList, savePath: path, startNow: startNow) }
        if !files.isEmpty { model.add(files: files, savePath: path, startNow: startNow) }
        dismiss()
    }
}
