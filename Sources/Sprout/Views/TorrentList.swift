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
                SeedBed(torrent: torrent, selected: model.selection.contains(torrent.id))
                    .listRowSeparator(.hidden)
                    // Fixed insets: rows put back after a search otherwise came back 8 pt taller.
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
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
    /// A selected row drops the orange (unreadable on the grey graphite highlight) and draws its
    /// dots in the text's own style, so they turn white on a focused highlight and stay dark on an
    /// unfocused one, exactly like the name. `backgroundProminence` never reports the change here.
    var selected = false

    var body: some View {
        let onSelection = selected
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Text(torrent.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(torrent.name)
                PieceTray(torrent: torrent, selected: onSelection)
                    .inkOnSelection(onSelection, torrent.state.isStopped ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                statusLine(onSelection)
                    .font(.callout)
                    .foregroundStyle(onSelection ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            }
            DotText(text: Format.percentDigits(torrent.progress), dot: 3.5,
                    color: onSelection && !torrent.state.isError ? .white : torrent.figureColor,
                    showsUnlit: !onSelection)
                .inkOnSelection(onSelection && !torrent.state.isError,
                                torrent.state.isStopped ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .frame(minWidth: 90, alignment: .trailing)
        }
        .padding(.horizontal, 4)
        // Every bed has the same height: a strict grid, and no stale row heights as content arrives.
        .frame(height: SeedBed.height)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(torrent.name), \(torrent.state.label), \(Format.percent(torrent.progress))")
    }

    private func statusLine(_ onSelection: Bool) -> some View {
        HStack(spacing: 14) {
            Label(torrent.state.label, systemImage: torrent.state.symbol)
                .foregroundStyle(torrent.state.isError ? Color.fault : Color.secondary)
            if torrent.downloadSpeed >= Format.movingThreshold && torrent.progress < 1 {
                Label(Format.speed(torrent.downloadSpeed), systemImage: "arrow.down")
                    .foregroundStyle(onSelection ? Color.primary : Color.signal)
            }
            if torrent.uploadSpeed >= Format.movingThreshold {
                Label(Format.speed(torrent.uploadSpeed), systemImage: "arrow.up")
                    .foregroundStyle(onSelection ? Color.primary : Color.signal)
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

private extension View {
    /// Repaints a white drawing in a text style, which the List adapts to the selection highlight.
    @ViewBuilder
    func inkOnSelection(_ selected: Bool, _ style: AnyShapeStyle) -> some View {
        if selected {
            hidden().overlay { Rectangle().fill(style).mask { self } }
        } else {
            self
        }
    }
}
