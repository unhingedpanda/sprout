import SwiftUI

/// Where a category's torrents are saved. Torrents follow it while "Use Category Folder" is on.
struct CategorySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let category: String

    @State private var folder = ""
    @State private var choosing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section {
                    LabeledContent("Save to") {
                        HStack {
                            Text(folder.isEmpty ? "A “\(category)” folder in the default folder" : URL(filePath: folder).lastPathComponent)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .help(folder)
                            Button("Change…") { choosing = true }
                                .fileImporter(isPresented: $choosing, allowedContentTypes: [.folder]) { result in
                                    if case .success(let url) = result { folder = url.path }
                                }
                        }
                    }
                    if !folder.isEmpty {
                        Button("Use the Default Location") { folder = "" }
                    }
                } footer: {
                    Text("Torrents in this category that use the category folder move here. Turn that on per torrent in the Torrent menu, or for new torrents in Settings › Downloads.")
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    model.setCategoryFolder(category, to: folder)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 440)
        .navigationTitle("Category “\(category)”")
        .onAppear { folder = model.categoryFolders[category] ?? "" }
    }
}
