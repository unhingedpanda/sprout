import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.engine.status {
        case .running:
            MainView()
        case .stopped, .starting:
            ProgressView("Starting the torrent engine…")
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("The torrent engine isn't running", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
                    .textSelection(.enabled)
            } actions: {
                Button("Try Again") { Task { await model.start() } }
                    .keyboardShortcut(.defaultAction)
                Button("Show Engine Log") {
                    NSWorkspace.shared.activateFileViewerSelecting([EngineController.logURL])
                }
            }
        }
    }
}
