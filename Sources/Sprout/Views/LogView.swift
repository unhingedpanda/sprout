import SwiftUI

/// The engine's own log: what it did and why, plus peers it refused.
struct LogView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("logSection") private var section = Section.messages
    @AppStorage("logProblemsOnly") private var problemsOnly = false
    @State private var search = ""
    @State private var messages: [Entry] = []
    @State private var blocked: [Entry] = []

    enum Section: String { case messages, blocked }

    struct Entry: Identifiable {
        enum Kind { case normal, info, warning, critical, blocked }
        let id: Int
        let date: Date
        let text: String
        let kind: Kind
    }

    private var rows: [Entry] {
        let source = section == .messages ? messages : blocked
        let query = search.trimmingCharacters(in: .whitespaces)
        return source.reversed().filter { entry in
            (!problemsOnly || section == .blocked || entry.kind == .warning || entry.kind == .critical)
                && (query.isEmpty || entry.text.localizedStandardContains(query))
        }
    }

    var body: some View {
        List(rows) { entry in
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(entry.date, format: .dateTime.hour().minute().second())
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 76, alignment: .leading)
                if let label = label(entry.kind) {
                    label.font(.callout).fixedSize()
                        // Ink for warnings, the fault colour (always with a word) for errors; never the accent.
                        .foregroundStyle(entry.kind == .critical ? Color.fault : Color.primary)
                }
                Text(entry.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contextMenu {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.text, forType: .string)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.ground)
        .overlay {
            if rows.isEmpty {
                if !search.isEmpty {
                    ContentUnavailableView.search(text: search)
                } else if section == .blocked {
                    ContentUnavailableView("No peers blocked", systemImage: "hand.raised",
                                           description: Text("Peers you ban, and peers your IP filter refuses, are listed here."))
                } else {
                    ContentUnavailableView(problemsOnly ? "No warnings or errors" : "Nothing logged yet", systemImage: "text.page")
                }
            }
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Filter")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Log", selection: $section) {
                    Text("Messages").tag(Section.messages)
                    Text("Blocked Peers").tag(Section.blocked)
                }
                .pickerStyle(.segmented)
            }
            ToolbarItem {
                Toggle("Warnings and Errors Only", systemImage: "exclamationmark.triangle", isOn: $problemsOnly)
                    .disabled(section == .blocked)
                    .help("Show only warnings and errors")
            }
        }
        .navigationTitle("Engine Log")
        .tint(.lit)
        .task(id: model.engine.api?.baseURL) { await poll() }
    }

    private func label(_ kind: Entry.Kind) -> Label<Text, Image>? {
        switch kind {
        case .warning: Label("Warning", systemImage: "exclamationmark.triangle")
        case .critical: Label("Error", systemImage: "xmark.octagon")
        default: nil
        }
    }

    /// Reads new lines every two seconds, from the last one already shown.
    private func poll() async {
        guard let api = model.engine.api else { return }
        messages = []
        blocked = []
        while !Task.isCancelled {
            let lastMessage = messages.last?.id ?? -1
            let lastBlocked = blocked.last?.id ?? -1
            if let data = try? await api.fetch("log/main", ["last_known_id": String(lastMessage)]),
               let list = try? JSON.decode(data).array {
                messages += list.compactMap(Self.message)
            }
            if let data = try? await api.fetch("log/peers", ["last_known_id": String(lastBlocked)]),
               let list = try? JSON.decode(data).array {
                blocked += list.compactMap(Self.peer)
            }
            // The engine keeps its own cap; keep the window responsive on long sessions.
            if messages.count > 5000 { messages.removeFirst(messages.count - 5000) }
            try? await Task.sleep(for: .seconds(2))
        }
    }

    private static func message(_ json: JSON) -> Entry? {
        guard let id = json["id"]?.int else { return nil }
        let kind: Entry.Kind = switch json["type"]?.int ?? 1 {
        case 2: .info
        case 4: .warning
        case 8: .critical
        default: .normal
        }
        return Entry(id: Int(id), date: date(json), text: json["message"]?.string ?? "", kind: kind)
    }

    private static func peer(_ json: JSON) -> Entry? {
        guard let id = json["id"]?.int else { return nil }
        let ip = json["ip"]?.string ?? ""
        let reason = json["reason"]?.string ?? ""
        let blocked = json["blocked"]?.bool ?? true
        let text = blocked ? "\(ip) blocked. \(reason)" : "\(ip) banned. \(reason)"
        return Entry(id: Int(id), date: date(json), text: text.trimmingCharacters(in: .whitespaces), kind: .blocked)
    }

    /// The engine sends seconds since 1970.
    private static func date(_ json: JSON) -> Date {
        Date(timeIntervalSince1970: json["timestamp"]?.double ?? 0)
    }
}
