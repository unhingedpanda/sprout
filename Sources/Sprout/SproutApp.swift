import SwiftUI
import UserNotifications

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

        Settings {
            SettingsView().environment(appDelegate.model)
        }

        Window("Engine Log", id: "log") {
            LogView()
                .environment(appDelegate.model)
                .frame(minWidth: 560, minHeight: 300)
        }
        .defaultSize(width: 820, height: 520)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let model = AppModel()
    private var isTerminating = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        if Preferences.notifyOnCompletion {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        Task { await model.start() }
    }

    // Show "Download finished" even while Sprout is in front.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    // Clicking the notification selects that torrent.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let hash = response.notification.request.content.userInfo["hash"] as? String else { return }
        await MainActor.run {
            model.sidebar = .state(.all)
            model.selection = [hash]
            NSApp.activate()
        }
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
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Add Torrent…") { model.showsAddSheet = true }
                .keyboardShortcut("o")
            Button("Create Torrent…") { model.showsCreateSheet = true }
                .keyboardShortcut("n", modifiers: [.command, .shift])
        }
        CommandGroup(before: .windowList) {
            Button("Engine Log") { openWindow(id: "log") }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            Divider()
        }
        CommandMenu("Torrent") {
            TorrentActions(model: model, hashes: model.selection, showsShortcuts: true)
        }
        CommandGroup(after: .toolbar) {
            Button(model.server.usesAlternativeSpeeds ? "Use Normal Speeds" : "Use Alternative Speeds") {
                model.toggleAlternativeSpeeds()
            }
            .keyboardShortcut("l", modifiers: [.command, .option])
        }
        CommandGroup(after: .sidebar) {
            Button(model.showsInspector ? "Hide Inspector" : "Show Inspector") {
                model.showsInspector.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
        }
    }
}
