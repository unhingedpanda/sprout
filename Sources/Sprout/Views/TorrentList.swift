import SwiftUI

/// The torrent list as a tray of seed beds: one row per torrent, its pieces drawn full width.
struct TorrentList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let rows = model.visibleTorrents

        VStack(spacing: 0) {
            PulseBand(history: model.speedHistory,
                      current: SpeedSample(down: model.server.downloadSpeed, up: model.server.uploadSpeed))

            List(rows, selection: $model.selection) { torrent in
                SeedBed(torrent: torrent)
                    .listRowSeparator(.hidden)
            }
            .listStyle(.inset)
            // The List's own row height; a frame on the row alone isn't honoured for rows
            // inserted while the window is hidden or off screen.
            .environment(\.defaultMinListRowHeight, SeedBed.height)
            .scrollContentBackground(.hidden)
            .alternatingRowBackgrounds(.disabled)
            .contextMenu(forSelectionType: String.self) { hashes in
                rowMenu(hashes)
            } primaryAction: { hashes in
                if hashes.count == 1, let torrent = hashes.first.flatMap({ model.torrents[$0] }) {
                    model.revealInFinder(torrent)
                }
            }
            .overlay {
                if rows.isEmpty { emptyState }
            }
            .overlay(alignment: .bottom) { NoticeBanner() }
        }
        .background(Color.ground)
    }

    @ViewBuilder
    private func rowMenu(_ hashes: Set<String>) -> some View {
        if !hashes.isEmpty { TorrentActions(model: model, hashes: hashes) }
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.torrents.isEmpty {
            VStack(spacing: 18) {
                EmptyMatrix()
                VStack(spacing: 6) {
                    Text("Nothing here yet")
                        .font(.title3.weight(.semibold))
                    Text("Open a magnet link from your browser, or drop .torrent files here.")
                        .foregroundStyle(.secondary)
                }
                Button("Add Torrent…") { model.showsAddSheet = true }
                    .controlSize(.large)
            }
            .multilineTextAlignment(.center)
            .padding()
        } else if !model.searchText.isEmpty {
            ContentUnavailableView.search(text: model.searchText)
        } else {
            ContentUnavailableView("Nothing in \(model.sidebar.title)", systemImage: model.sidebar.symbol)
        }
    }
}

/// One torrent: name, full-width tray, a large percentage in the state colour, and one quiet status line.
struct SeedBed: View {
    static let height: CGFloat = 70
    let torrent: Torrent

    @Environment(\.backgroundProminence) private var prominence

    var body: some View {
        let onSelection = prominence == .increased
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Text(torrent.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(torrent.name)
                PieceTray(torrent: torrent)
                statusLine
                    .font(.callout)
                    .foregroundStyle(onSelection ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            }
            DotText(text: Format.percentDigits(torrent.progress), dot: 3.5,
                    color: onSelection ? .white : torrent.figureColor,
                    showsUnlit: !onSelection)
                .frame(minWidth: 90, alignment: .trailing)
        }
        .padding(.horizontal, 4)
        // Every bed has the same height: a strict grid, and no stale row heights as content arrives.
        .frame(height: SeedBed.height)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(torrent.name), \(torrent.state.label), \(Format.percent(torrent.progress))")
    }

    private var statusLine: some View {
        HStack(spacing: 14) {
            Label(torrent.state.label, systemImage: torrent.state.symbol)
                .foregroundStyle(torrent.state.isError ? Color.fault : Color.secondary)
            if torrent.downloadSpeed >= Format.movingThreshold {
                Label(Format.speed(torrent.downloadSpeed), systemImage: "arrow.down")
                    .foregroundStyle(Color.signal)
            }
            if torrent.uploadSpeed >= Format.movingThreshold {
                Label(Format.speed(torrent.uploadSpeed), systemImage: "arrow.up")
                    .foregroundStyle(Color.signal)
            }
            if torrent.hasKnownETA {
                Text("\(Format.eta(torrent)) left")
            }
            Spacer(minLength: 0)
            if torrent.size > 0 {
                Text(Format.bytes(torrent.size))
            }
            if torrent.ratio >= 0.01 {
                Text("Ratio \(Format.ratio(torrent.ratio))")
            }
        }
        .labelStyle(CompactLabelStyle())
        .monospacedDigit()
        .lineLimit(1)
    }
}

private struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}

struct StatusLabel: View {
    let state: TorrentState

    var body: some View {
        Label(state.label, systemImage: state.symbol)
            .foregroundStyle(state.isError ? Color.fault : Color.primary)
            .lineLimit(1)
    }
}
