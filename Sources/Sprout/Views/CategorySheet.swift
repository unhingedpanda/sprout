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
            SheetHeader(title: "Folder for “\(category)”")
            Form {
                Section {
                    LabeledContent("Save to") {
                        HStack {
                            Text(folder.isEmpty ? "Default location › \(category)" : URL(filePath: folder).lastPathComponent)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
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
            .sheetForm()
        }
        .sproutSheet(width: 440)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel", role: .cancel) { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    model.setCategoryFolder(category, to: folder)
                    dismiss()
                }
                .tint(.action)
            }
        }
        .onAppear { folder = model.categoryFolders[category] ?? "" }
    }
}
