import SwiftUI

@main
struct SproutApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Sprout", id: "main") {
            RootView()
                .environment(appDelegate.model)
                .frame(minWidth: 760, minHeight: 420)
        }
        .defaultSize(width: 1380, height: 760)
        .commands { SproutCommands(model: appDelegate.model) }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var isTerminating = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await model.start() }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        model.open(urls)
    }

    // Torrents keep downloading and seeding with the window closed, like other Mac clients.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isTerminating else { return .terminateLater }
        isTerminating = true
        Task {
            await model.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

struct SproutCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Add Torrent…") { model.showsAddSheet = true }
                .keyboardShortcut("o")
        }
        CommandMenu("Torrent") {
            Button("Start") { model.startSelected() }
                .keyboardShortcut("r")
                .disabled(!model.canStart)
            Button("Stop") { model.stopSelected() }
                .keyboardShortcut(".")
                .disabled(!model.canStop)
            Divider()
            Button("Show in Finder") {
                if let torrent = model.selectedTorrents.first { model.revealInFinder(torrent) }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(model.selection.count != 1)
            Divider()
            Button("Remove…") { model.requestRemoveSelected() }
                .keyboardShortcut(.delete)
                .disabled(model.selection.isEmpty)
        }
        CommandGroup(after: .sidebar) {
            Button(model.showsInspector ? "Hide Inspector" : "Show Inspector") {
                model.showsInspector.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
        }
    }
}
