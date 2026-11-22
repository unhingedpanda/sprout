import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        content
            .onAppear(perform: bringWindowsOnScreen)
    }

    /// A window saved on a display that's gone, or off every screen, comes back to the centre.
    private func bringWindowsOnScreen() {
        DispatchQueue.main.async {
            for window in NSApp.windows where window.canBecomeMain && !window.isMiniaturized {
                let onScreen = NSScreen.screens.contains { screen in
                    let overlap = screen.visibleFrame.intersection(window.frame)
                    return overlap.width >= 200 && overlap.height >= 120
                }
                if !onScreen && window.frame.width > 0 { window.center() }
            }
        }
    }

    private var content: some View {
        // MainView sets these too; the starting and failed screens need them as well.
        status.containerBackground(Color.ground, for: .window).tint(.lit)
    }

    @ViewBuilder
    private var status: some View {
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
