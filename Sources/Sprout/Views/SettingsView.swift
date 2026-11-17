import ServiceManagement
import SwiftUI

/// Sprout's Settings window. Engine settings are read from the engine when the window opens
/// and written back one change at a time; Sprout's own settings live in UserDefaults.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var settings = EngineSettings()
    /// Settings reopens on the tab used last, like other Mac apps.
    @AppStorage("SettingsTab") private var tab = "General"

    var body: some View {
        TabView(selection: $tab) {
            Tab("General", systemImage: "gearshape", value: "General") { GeneralSettings(settings: settings) }
            Tab("Speed", systemImage: "speedometer", value: "Speed") { SpeedSettings(settings: settings) }
            Tab("Seeding", systemImage: "arrow.up.circle", value: "Seeding") { SeedingSettings(settings: settings) }
            Tab("Queue", systemImage: "list.number", value: "Queue") { QueueSettings(settings: settings) }
            Tab("Connection", systemImage: "network", value: "Connection") { ConnectionSettings(settings: settings) }
        }
        .frame(width: 520)
        .task(id: model.engine.api?.baseURL) { await settings.load(model.engine.api) }
    }
}

@MainActor @Observable
final class EngineSettings {
    private(set) var values: [String: JSON] = [:]
    private(set) var api: WebAPI?
    var message: String?

    var isLoaded: Bool { !values.isEmpty }

    func load(_ api: WebAPI?) async {
        self.api = api
        guard let api else { message = "Settings are available once the engine is running."; return }
        do {
            values = try await api.preferences()
            message = nil
        } catch {
            message = "Sprout couldn't read the engine's settings. \(error.localizedDescription)"
        }
    }

    func set(_ changes: [String: JSON]) {
        values.merge(changes) { $1 }
        guard let api else { return }
        Task {
            do { try await api.setPreferences(changes) } catch {
                message = "Sprout couldn't save that setting. \(error.localizedDescription)"
            }
        }
    }

    /// A switch. `startingAt` names a value key to fill in when the switch turns on and the
    /// value is unset (the engine reports -1), since some switches mean nothing without one.
    func flag(_ key: String, startingAt value: (key: String, default: Double)? = nil) -> Binding<Bool> {
        Binding(get: { self.values[key]?.bool ?? false }, set: { on in
            var changes: [String: JSON] = [key: .bool(on)]
            if on, let value, (self.values[value.key]?.double ?? -1) < 0 { changes[value.key] = .number(value.default) }
            self.set(changes)
        })
    }

    /// A number shown in its own unit: `scale` engine units make one shown unit.
    func number(_ key: String, scale: Double = 1, whole: Bool = true) -> Binding<Double> {
        Binding(
            get: { max(0, self.values[key]?.double ?? 0) / scale },
            set: { value in
                let raw = max(0, value) * scale
                self.set([key: .number(whole ? raw.rounded() : raw)])
            }
        )
    }
}

/// The engine's settings form: a message while loading or failing, otherwise the content.
private struct SettingsForm<Content: View>: View {
    let settings: EngineSettings
    @ViewBuilder var content: Content

    var body: some View {
        Form {
            if settings.isLoaded {
                content
            } else {
                Text(settings.message ?? "Reading the engine's settings…")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
        .overlay(alignment: .bottom) {
            if settings.isLoaded, let message = settings.message {
                Text(message).font(.caption).foregroundStyle(Color.fault).padding(8)
            }
        }
    }
}

/// A number field with its unit, aligned the way macOS Settings aligns values.
private struct UnitField: View {
    let title: String
    @Binding var value: Double
    let unit: String
    var fraction = false

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                TextField(title, value: $value, format: .number.precision(.fractionLength(fraction ? 0...2 : 0...0)))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                Text(unit).foregroundStyle(.secondary)
            }
        }
    }
}

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    let settings: EngineSettings
    @AppStorage(Preferences.notifyOnCompletionKey) private var notify = true
    @AppStorage(Preferences.preventSleepKey) private var preventSleep = true
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var choosingFolder = false

    var body: some View {
        SettingsForm(settings: settings) {
            Section {
                LabeledContent("Save downloads to") {
                    HStack {
                        let path = settings.values.string("save_path")
                        Text(URL(filePath: path).lastPathComponent)
                            .help(path)
                        Button("Change…") { choosingFolder = true }
                            .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
                                if case .success(let url) = result { settings.set(["save_path": .string(url.path)]) }
                            }
                    }
                }
            }
            Section {
                Toggle("Notify when a download finishes", isOn: $notify)
                Toggle("Keep the Mac awake while downloading", isOn: $preventSleep)
                    .onChange(of: preventSleep) { model.holdSleepWhileDownloading() }
                Toggle("Open Sprout at login", isOn: $opensAtLogin)
                    .onChange(of: opensAtLogin) { _, on in setOpensAtLogin(on) }
            } footer: {
                if let loginError { Text(loginError).foregroundStyle(Color.fault) }
            }
        }
    }

    private func setOpensAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "macOS didn't allow that. \(error.localizedDescription)"
        }
        opensAtLogin = SMAppService.mainApp.status == .enabled
    }
}

private struct SpeedSettings: View {
    let settings: EngineSettings

    var body: some View {
        SettingsForm(settings: settings) {
            Section {
                UnitField(title: "Download", value: settings.number("dl_limit", scale: 1024), unit: "KB/s")
                UnitField(title: "Upload", value: settings.number("up_limit", scale: 1024), unit: "KB/s")
            } header: {
                Text("Normal limits")
            } footer: {
                Text("0 means no limit.")
            }
            Section {
                UnitField(title: "Download", value: settings.number("alt_dl_limit", scale: 1024), unit: "KB/s")
                UnitField(title: "Upload", value: settings.number("alt_up_limit", scale: 1024), unit: "KB/s")
            } header: {
                Text("Alternative limits")
            } footer: {
                Text("Switch to these with the tortoise in the toolbar or ⌥⌘L, for example while you need the connection for something else.")
            }
        }
    }
}

private struct SeedingSettings: View {
    let settings: EngineSettings

    var body: some View {
        SettingsForm(settings: settings) {
            Section {
                // The engine ignores the switch alone: turning it on also sends a starting value.
                Toggle("Stop at a share ratio", isOn: settings.flag("max_ratio_enabled", startingAt: ("max_ratio", 2)))
                if settings.values["max_ratio_enabled"]?.bool == true {
                    UnitField(title: "Ratio", value: settings.number("max_ratio", whole: false), unit: "× size", fraction: true)
                }
                Toggle("Stop after a seeding time", isOn: settings.flag("max_seeding_time_enabled", startingAt: ("max_seeding_time", 24 * 60)))
                if settings.values["max_seeding_time_enabled"]?.bool == true {
                    UnitField(title: "Time", value: settings.number("max_seeding_time", scale: 60), unit: "hours")
                }
                Picker("When a limit is reached", selection: Binding(
                    get: { Int(settings.values.int("max_ratio_act")) },
                    set: { settings.set(["max_ratio_act": .number(Double($0))]) }
                )) {
                    Text("Stop the torrent").tag(0)
                    Text("Remove the torrent").tag(1)
                    Text("Remove the torrent and its files").tag(3)
                }
            } footer: {
                Text("Torrents seed until you stop them unless a limit is set.")
            }
        }
    }
}

private struct QueueSettings: View {
    let settings: EngineSettings

    var body: some View {
        SettingsForm(settings: settings) {
            Section {
                Toggle("Limit how many torrents run at once", isOn: settings.flag("queueing_enabled"))
                if settings.values["queueing_enabled"]?.bool == true {
                    UnitField(title: "Downloading", value: settings.number("max_active_downloads"), unit: "at once")
                    UnitField(title: "Seeding", value: settings.number("max_active_uploads"), unit: "at once")
                    UnitField(title: "In total", value: settings.number("max_active_torrents"), unit: "at once")
                }
            } footer: {
                Text("Torrents over the limit wait in the queue. Force Start skips it.")
            }
        }
    }
}

private struct ConnectionSettings: View {
    let settings: EngineSettings

    var body: some View {
        SettingsForm(settings: settings) {
            Section {
                LabeledContent("Listening port") {
                    TextField("Listening port", value: Binding(
                        get: { Int(settings.values.int("listen_port")) },
                        set: { if (1...65535).contains($0) { settings.set(["listen_port": .number(Double($0))]) } }
                    ), format: .number.grouping(.never))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                }
                Toggle("Open the port on the router automatically", isOn: settings.flag("upnp"))
            } footer: {
                Text("Other peers connect to this port. Change it only if your network needs a specific one.")
            }
        }
    }
}
