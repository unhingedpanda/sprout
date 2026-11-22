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
                SeedBed(torrent: torrent, selected: model.selection.contains(torrent.id),
                        finishedAt: model.finishedAt[torrent.id], clock: model.bloomClock)
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
    /// When the download finished this session. A change plays the bloom: a green sweep through the
    /// tray, and the figure says DONE for a few seconds.
    var finishedAt: Date?
    /// The model's bloom clock: it only moves during a finish, so the row redraws only then.
    var clock = Date.now
    #if DEBUG
    /// Snapshots only: holds the bloom sweep at a fixed point.
    var bloomPreview: Double?
    var donePreview = false
    #endif

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // The bloom runs off the model's finish time and clock. Row state, tasks and TimelineView
        // didn't survive or tick inside the list's rows, which cut the bloom short.
        bed(at: clock)
    }

    private func bed(at date: Date) -> some View {
        let age = finishedAt.map { date.timeIntervalSince($0) } ?? .infinity
        let saysDone = age >= 0 && age < 4
        let bloom = reduceMotion || !(age >= 0 && age < Self.sweep) ? 1 : 1 - pow(1 - age / Self.sweep, 3)
        let onSelection = selected
        return HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Text(torrent.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(torrent.name)
                PieceTray(torrent: torrent, selected: onSelection, bloom: previewed(bloom))
                    .inkOnSelection(onSelection, torrent.state.isStopped ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                statusLine(onSelection)
                    .font(.callout)
                    .foregroundStyle(onSelection ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            }
            DotText(text: showsDone(saysDone) ? "DONE" : Format.percentDigits(torrent.progress), dot: 3.5,
                    color: onSelection && !torrent.state.isError ? .white : (showsDone(saysDone) ? .growth : torrent.figureColor),
                    showsUnlit: !onSelection)
                .inkOnSelection(onSelection && !torrent.state.isError,
                                torrent.state.isStopped ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                // Wide enough for DONE, so the tray doesn't jump when a download finishes.
                .frame(minWidth: 104, alignment: .trailing)
        }
        .padding(.horizontal, 4)
        // Every bed has the same height: a strict grid, and no stale row heights as content arrives.
        .frame(height: SeedBed.height)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(torrent.name), \(torrent.state.label), \(Format.percent(torrent.progress))")
    }

    private static let sweep = 1.4

    private func showsDone(_ saysDone: Bool) -> Bool {
        #if DEBUG
        if donePreview { return true }
        #endif
        return saysDone
    }

    private func previewed(_ bloom: Double) -> Double {
        #if DEBUG
        if let bloomPreview { return bloomPreview }
        #endif
        return bloom
    }

    private func statusLine(_ onSelection: Bool) -> some View {
        HStack(spacing: 14) {
            Label {
                Text(torrent.state.label)
                    .foregroundStyle(torrent.state.isError && !onSelection ? Color.fault : Color.secondary)
            } icon: {
                Image(systemName: torrent.state.symbol)
                    .foregroundStyle(onSelection ? Color.primary : torrent.state.tint)
            }
            .animation(.easeOut(duration: 0.2), value: torrent.state)
            if torrent.isFetching {
                Label(Format.speed(torrent.downloadSpeed), systemImage: "arrow.down")
                    .foregroundStyle(onSelection ? Color.primary : Color.signal)
            }
            if torrent.isGiving {
                Label(Format.speed(torrent.uploadSpeed), systemImage: "arrow.up")
                    .foregroundStyle(onSelection ? Color.primary : Color.growth)
            }
            if torrent.hasKnownETA {
                Text("\(Format.eta(torrent)) left")
            }
            Spacer(minLength: 0)
            if torrent.size > 0 {
                Text(Format.bytes(torrent.size))
            }
            if torrent.ratio >= 0.01 {
                // A leaf once it has given back as much as it took.
                if torrent.ratio >= 1 {
                    Label("Ratio \(Format.ratio(torrent.ratio))", systemImage: "leaf.fill")
                        .labelStyle(LeafLabelStyle(tint: onSelection ? .primary : .growth))
                        .help("Shared back at least as much as it downloaded")
                } else {
                    Text("Ratio \(Format.ratio(torrent.ratio))")
                }
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

private struct LeafLabelStyle: LabelStyle {
    let tint: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.imageScale(.small).foregroundStyle(tint)
            configuration.title
        }
    }
}

struct StatusLabel: View {
    let state: TorrentState

    var body: some View {
        Label {
            Text(state.label).foregroundStyle(state.isError ? Color.fault : Color.primary)
        } icon: {
            Image(systemName: state.symbol).foregroundStyle(state.tint)
        }
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
