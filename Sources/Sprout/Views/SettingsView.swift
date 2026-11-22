import ServiceManagement
import SystemConfiguration
import SwiftUI
import UniformTypeIdentifiers

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
            Tab("Downloads", systemImage: "arrow.down.circle", value: "Downloads") { DownloadSettings(settings: settings) }
            Tab("Speed", systemImage: "speedometer", value: "Speed") { SpeedSettings(settings: settings) }
            Tab("Seeding", systemImage: "arrow.up.circle", value: "Seeding") { SeedingSettings(settings: settings) }
            Tab("Queue", systemImage: "list.number", value: "Queue") { QueueSettings(settings: settings) }
            Tab("Connection", systemImage: "network", value: "Connection") { ConnectionSettings(settings: settings) }
            Tab("Privacy", systemImage: "lock.shield", value: "Privacy") { PrivacySettings(settings: settings) }
        }
        .frame(width: 600)
        .tint(.lit)
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

    /// A whole number the engine stores as a code, for pickers.
    func integer(_ key: String) -> Binding<Int> {
        Binding(get: { Int(self.values.int(key)) }, set: { self.set([key: .number(Double($0))]) })
    }

    func text(_ key: String) -> Binding<String> {
        Binding(get: { self.values.string(key) }, set: { self.set([key: .string($0)]) })
    }

    /// A number shown in its own unit: `scale` engine units make one shown unit.
    /// `zeroIsUnlimited` is for engine values where 0 means "none allowed" and -1 means "no limit":
    /// the field shows -1 as 0 and writes 0 as -1, matching the "0 means no limit" used elsewhere.
    func number(_ key: String, scale: Double = 1, whole: Bool = true, zeroIsUnlimited: Bool = false) -> Binding<Double> {
        Binding(
            get: { max(0, self.values[key]?.double ?? 0) / scale },
            set: { value in
                let raw = max(0, value) * scale
                let stored = zeroIsUnlimited && raw == 0 ? -1 : (whole ? raw.rounded() : raw)
                self.set([key: .number(stored)])
            }
        )
    }
}

/// The engine's settings form: a message while loading or failing, otherwise the content.
private struct SettingsForm<Content: View>: View {
    let settings: EngineSettings
    /// Long tabs scroll inside a fixed height instead of growing past the screen.
    var scrolls = false
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
        .scrollDisabled(!scrolls)
        .frame(height: scrolls ? 440 : nil)
        .fixedSize(horizontal: false, vertical: !scrolls)
        .overlay(alignment: .bottom) {
            if settings.isLoaded, let message = settings.message {
                Text(message).font(.caption).foregroundStyle(Color.fault).padding(8)
            }
        }
    }
}

/// A number field with its unit, aligned the way macOS Settings aligns values.
struct UnitField: View {
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

    var body: some View {
        SettingsForm(settings: settings) {
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
        SettingsForm(settings: settings, scrolls: true) {
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
            Section {
                Toggle("Use alternative limits on a schedule", isOn: settings.flag("scheduler_enabled"))
                if settings.values["scheduler_enabled"]?.bool == true {
                    TimeField(title: "From", settings: settings, hour: "schedule_from_hour", minute: "schedule_from_min")
                    TimeField(title: "To", settings: settings, hour: "schedule_to_hour", minute: "schedule_to_min")
                    Picker("On", selection: settings.integer("scheduler_days")) {
                        Text("Every day").tag(0)
                        Text("Weekdays").tag(1)
                        Text("Weekends").tag(2)
                        Divider()
                        ForEach(Array(Calendar.current.weekdaySymbols.enumerated()), id: \.offset) { index, name in
                            // The engine counts Monday as 3 through Sunday as 9; Calendar starts on Sunday.
                            Text(name).tag(index == 0 ? 9 : index + 2)
                        }
                    }
                }
            } footer: {
                if settings.values["scheduler_enabled"]?.bool == true {
                    Text("Outside these hours the normal limits apply. The toolbar tortoise still overrides the schedule.")
                }
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
                Toggle("Stop after a time without uploads", isOn: settings.flag("max_inactive_seeding_time_enabled", startingAt: ("max_inactive_seeding_time", 60)))
                if settings.values["max_inactive_seeding_time_enabled"]?.bool == true {
                    UnitField(title: "Idle", value: settings.number("max_inactive_seeding_time"), unit: "minutes")
                }
                Picker("When a limit is reached", selection: Binding(
                    get: { Int(settings.values.int("max_ratio_act")) },
                    set: { settings.set(["max_ratio_act": .number(Double($0))]) }
                )) {
                    Text("Stop the torrent").tag(0)
                    Text("Remove the torrent").tag(1)
                    Text("Remove the torrent and its files").tag(3)
                    Text("Switch to super seeding").tag(2)
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
                    UnitField(title: "Downloading", value: settings.number("max_active_downloads", zeroIsUnlimited: true), unit: "at once")
                    UnitField(title: "Seeding", value: settings.number("max_active_uploads", zeroIsUnlimited: true), unit: "at once")
                    UnitField(title: "In total", value: settings.number("max_active_torrents", zeroIsUnlimited: true), unit: "at once")
                }
            } footer: {
                Text("Torrents over the limit wait in the queue. Force Start skips it. 0 means no limit.")
            }
        }
    }
}

private struct ConnectionSettings: View {
    let settings: EngineSettings
    @State private var interfaces: [(name: String, value: String)] = []

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
            Section {
                Picker("Network interface", selection: Binding(
                    get: { settings.values.string("current_network_interface") },
                    set: { settings.set(["current_network_interface": .string($0), "current_interface_address": .string("")]) }
                )) {
                    Text("Any").tag("")
                    ForEach(interfaces, id: \.value) { Text($0.name).tag($0.value) }
                }
            } footer: {
                Text("Pick your VPN's interface to keep torrents off the network when the VPN is down. VPNs usually appear as a tunnel.")
            }
            Section {
                UnitField(title: "Connections in total", value: settings.number("max_connec"), unit: "peers")
                UnitField(title: "Connections per torrent", value: settings.number("max_connec_per_torrent"), unit: "peers")
            } footer: {
                Text("0 means no limit.")
            }
        }
        .task {
            guard let api = settings.api, let data = try? await api.fetch("app/networkInterfaceList"),
                  let list = try? JSON.decode(data).array else { return }
            interfaces = list.compactMap { item in
                guard let value = item["value"]?.string else { return nil }
                return NetworkNames.label(value).map { ($0, value) }
            }
        }
    }
}

// MARK: Downloads

private struct DownloadSettings: View {
    @Environment(AppModel.self) private var model
    let settings: EngineSettings

    private var watchedFolders: [String] {
        (settings.values["scan_dirs"]?.object?.keys.map { $0 } ?? []).sorted()
    }

    var body: some View {
        SettingsForm(settings: settings, scrolls: true) {
            Section {
                FolderField(title: "Save downloads to", path: settings.values.string("save_path")) {
                    settings.set(["save_path": .string($0)])
                }
                Toggle("Keep unfinished downloads somewhere else", isOn: settings.flag("temp_path_enabled"))
                if settings.values["temp_path_enabled"]?.bool == true {
                    FolderField(title: "Unfinished downloads", path: settings.values.string("temp_path")) {
                        settings.set(["temp_path": .string($0)])
                    }
                }
                Toggle("Add .!qB to unfinished files", isOn: settings.flag("incomplete_files_ext"))
                Toggle("Save new torrents in their category's folder", isOn: settings.flag("auto_tmm_enabled"))
            } footer: {
                Text("Finished downloads move to the save folder. A category's folder is set from its menu in the sidebar.")
            }

            Section {
                Toggle("Merge its trackers into the one you have", isOn: Binding(
                    get: { settings.values["merge_trackers"]?.bool ?? false },
                    set: { on in
                        settings.set(["merge_trackers": .bool(on)])
                        model.mergesTrackers = on
                    }
                ))
            } header: {
                Text("When a torrent is added again")
            } footer: {
                Text("Adding the same torrent from another site then gives it that site's trackers too. Private torrents are never merged.")
            }

            Section {
                ForEach(watchedFolders, id: \.self) { path in
                    LabeledContent {
                        Button("Stop Watching", systemImage: "minus.circle") { unwatch(path) }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                    } label: {
                        Text(URL(filePath: path).lastPathComponent).help(path)
                    }
                }
                FolderButton(title: watchedFolders.isEmpty ? "Watch a Folder…" : "Watch Another Folder…") { watch($0) }
            } header: {
                Text("Watched folders")
            } footer: {
                Text(".torrent files that land in these folders are added by themselves and saved to the folder above.")
            }

            Section {
                Toggle("Skip files with these names", isOn: settings.flag("excluded_file_names_enabled"))
                if settings.values["excluded_file_names_enabled"]?.bool == true {
                    CommitField(title: "Names", text: settings.values.string("excluded_file_names"), prompt: "*.exe\nsample.*", lines: true) {
                        settings.set(["excluded_file_names": .string($0)])
                    }
                }
            } footer: {
                Text("One pattern per line. * matches any text. Matching files are set to Don't Download.")
            }

            Section {
                Toggle("When a torrent is added", isOn: settings.flag("autorun_on_torrent_added_enabled"))
                if settings.values["autorun_on_torrent_added_enabled"]?.bool == true {
                    CommitField(title: "Command", text: settings.values.string("autorun_on_torrent_added_program"),
                                prompt: "/usr/bin/say \"Added %N\"") {
                        settings.set(["autorun_on_torrent_added_program": .string($0)])
                    }
                }
                Toggle("When a download finishes", isOn: settings.flag("autorun_enabled"))
                if settings.values["autorun_enabled"]?.bool == true {
                    CommitField(title: "Command", text: settings.values.string("autorun_program"),
                                prompt: "/usr/bin/say \"%N finished\"") {
                        settings.set(["autorun_program": .string($0)])
                    }
                }
            } header: {
                Text("Run a command")
            } footer: {
                Text("%N name, %F content path, %D save folder, %L category, %G tags, %Z size in bytes, %I info hash. Put each in quotes, like \"%F\", so spaces don't split it.")
            }
        }
    }

    /// The engine takes the whole set of watched folders at once; 1 means "save to the default folder".
    private func watch(_ path: String) {
        var dirs = settings.values["scan_dirs"]?.object ?? [:]
        dirs[path] = .number(1)
        settings.set(["scan_dirs": .object(dirs)])
    }

    private func unwatch(_ path: String) {
        var dirs = settings.values["scan_dirs"]?.object ?? [:]
        dirs[path] = nil
        settings.set(["scan_dirs": .object(dirs)])
    }
}

// MARK: Privacy

private struct PrivacySettings: View {
    let settings: EngineSettings

    private var proxyType: String { settings.values.string("proxy_type") }

    var body: some View {
        SettingsForm(settings: settings, scrolls: true) {
            Section {
                Picker("Encryption", selection: settings.integer("encryption")) {
                    Text("Prefer encrypted connections").tag(0)
                    Text("Require encryption").tag(1)
                    Text("Never encrypt").tag(2)
                }
                Toggle("Anonymous mode", isOn: settings.flag("anonymous_mode"))
            } footer: {
                Text("Requiring encryption skips peers that don't support it. Anonymous mode hides Sprout's name, version and your listening port from peers and trackers.")
            }

            Section {
                Toggle("DHT, a shared directory of peers", isOn: settings.flag("dht"))
                Toggle("Peer exchange", isOn: settings.flag("pex"))
                Toggle("Local network discovery", isOn: settings.flag("lsd"))
            } header: {
                Text("Finding peers without trackers")
            } footer: {
                Text("Private torrents never use these.")
            }

            Section {
                // The engine only uses the proxy for torrents when proxy_bittorrent is on (it defaults off),
                // and proxy_misc covers its other connections. One switch here covers both.
                Picker("Proxy", selection: Binding(get: { proxyType.isEmpty ? "None" : proxyType },
                                                   set: { type in
                    let on = type != "None" && !settings.values.string("proxy_ip").isEmpty
                    settings.set(["proxy_type": .string(type), "proxy_bittorrent": .bool(on), "proxy_misc": .bool(on)])
                })) {
                    Text("None").tag("None")
                    Text("SOCKS5").tag("SOCKS5")
                    Text("HTTP").tag("HTTP")
                    Text("SOCKS4").tag("SOCKS4")
                }
                if !proxyType.isEmpty && proxyType != "None" {
                    CommitField(title: "Server", text: settings.values.string("proxy_ip"), prompt: "proxy.example.org") {
                        // Traffic starts going through the proxy only once it has an address.
                        settings.set(["proxy_ip": .string($0), "proxy_bittorrent": .bool(!$0.isEmpty), "proxy_misc": .bool(!$0.isEmpty)])
                    }
                    LabeledContent("Port") {
                        TextField("Port", value: Binding(
                            get: { Int(settings.values.int("proxy_port")) },
                            set: { if (1...65535).contains($0) { settings.set(["proxy_port": .number(Double($0))]) } }
                        ), format: .number.grouping(.never))
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    }
                    Toggle("Send peer connections through it", isOn: settings.flag("proxy_peer_connections"))
                    if proxyType != "SOCKS4" {
                        Toggle("Sign in to the proxy", isOn: settings.flag("proxy_auth_enabled"))
                        if settings.values["proxy_auth_enabled"]?.bool == true {
                            CommitField(title: "User name", text: settings.values.string("proxy_username")) {
                                settings.set(["proxy_username": .string($0)])
                            }
                            CommitField(title: "Password", text: "", prompt: "Unchanged", secure: true) {
                                if !$0.isEmpty { settings.set(["proxy_password": .string($0)]) }
                            }
                        }
                    }
                }
            } footer: {
                if !proxyType.isEmpty && proxyType != "None" {
                    Text(settings.values.string("proxy_ip").isEmpty
                         ? "Enter the proxy's server to start using it. Until then, connections go out directly."
                         : "Trackers go through the proxy. Peer connections do too while that switch is on.")
                }
            }

            Section {
                CommitField(title: "Banned addresses", text: settings.values.string("banned_IPs"), lines: true) {
                    settings.set(["banned_IPs": .string($0)])
                }
            } footer: {
                Text("Peers you ban from the inspector are listed here, one address per line. Delete a line to lift the ban.")
            }

            Section {
                Toggle("Block addresses from a filter list", isOn: settings.flag("ip_filter_enabled"))
                if settings.values["ip_filter_enabled"]?.bool == true {
                    FileField(title: "Filter list", path: settings.values.string("ip_filter_path"), extensions: ["dat", "p2p", "p2b"]) {
                        settings.set(["ip_filter_path": .string($0)])
                    }
                    Toggle("Apply it to trackers too", isOn: settings.flag("ip_filter_trackers"))
                }
            } header: {
                Text("IP filter")
            } footer: {
                Text("Takes eMule .dat, PeerGuardian .p2p and .p2b lists. Refused peers appear in Window › Engine Log.")
            }
        }
    }
}

// MARK: Fields

/// A text setting that saves when you press Return or leave the field, not on every key.
private struct CommitField: View {
    let title: String
    let text: String
    var prompt = ""
    var lines = false
    var secure = false
    let commit: (String) -> Void

    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if secure {
                SecureField(title, text: $draft, prompt: Text(prompt))
            } else if lines {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                    LinesEditor(text: $draft, placeholder: prompt)
                        .accessibilityLabel(title)
                }
            } else {
                TextField(title, text: $draft, prompt: Text(prompt))
            }
        }
        .focused($focused)
        .onSubmit(save)
        .onChange(of: focused) { if !focused { save() } }
        .onAppear { draft = text }
        .onDisappear(perform: save)
    }

    private func save() {
        let value = lines ? draft : draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if value != text && !(secure && value.isEmpty) { commit(value) }
    }
}

/// A folder setting: its name, and a button to pick another.
private struct FolderField: View {
    let title: String
    let path: String
    let choose: (String) -> Void

    var body: some View {
        LabeledContent(title) {
            HStack {
                Text(path.isEmpty ? "Not set" : URL(filePath: path).lastPathComponent)
                    .foregroundStyle(path.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .help(path)
                FolderButton(title: "Change…", choose: choose)
            }
        }
    }
}

private struct FolderButton: View {
    let title: String
    let choose: (String) -> Void
    @State private var choosing = false

    var body: some View {
        Button(title) { choosing = true }
            .fileImporter(isPresented: $choosing, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result { choose(url.path) }
            }
    }
}

private struct FileField: View {
    let title: String
    let path: String
    let extensions: [String]
    let choose: (String) -> Void
    @State private var choosing = false

    var body: some View {
        LabeledContent(title) {
            HStack {
                Text(path.isEmpty ? "None chosen" : URL(filePath: path).lastPathComponent)
                    .foregroundStyle(path.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .help(path)
                Button("Choose…") { choosing = true }
                    .fileImporter(isPresented: $choosing,
                                  allowedContentTypes: extensions.compactMap { UTType(filenameExtension: $0) }) { result in
                        if case .success(let url) = result { choose(url.path) }
                    }
            }
        }
    }
}

/// An hour and minute pair, stored by the engine as two numbers.
private struct TimeField: View {
    let title: String
    let settings: EngineSettings
    let hour: String
    let minute: String

    var body: some View {
        DatePicker(title, selection: Binding(
            get: {
                Calendar.current.date(bySettingHour: Int(settings.values.int(hour)), minute: Int(settings.values.int(minute)),
                                      second: 0, of: .now) ?? .now
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                settings.set([hour: .number(Double(parts.hour ?? 0)), minute: .number(Double(parts.minute ?? 0))])
            }
        ), displayedComponents: .hourAndMinute)
    }
}

/// Turns BSD interface names into what people recognise: "Wi-Fi (en0)", "VPN tunnel (utun3)".
/// Loopback and Apple's AirDrop/peer-to-peer links are left out: binding to them never makes sense.
private enum NetworkNames {
    static func label(_ bsdName: String) -> String? {
        if bsdName == "lo0" || bsdName.hasPrefix("awdl") || bsdName.hasPrefix("llw") { return nil }
        if bsdName.hasPrefix("utun") || bsdName.hasPrefix("ipsec") || bsdName.hasPrefix("ppp") {
            return "Tunnel (\(bsdName))"
        }
        if let name = displayNames[bsdName] { return "\(name) (\(bsdName))" }
        return bsdName
    }

    private static let displayNames: [String: String] = {
        var names: [String: String] = [:]
        for interface in (SCNetworkInterfaceCopyAll() as? [SCNetworkInterface]) ?? [] {
            if let bsd = SCNetworkInterfaceGetBSDName(interface) as String?,
               let name = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String? {
                names[bsd] = name
            }
        }
        return names
    }()
}
