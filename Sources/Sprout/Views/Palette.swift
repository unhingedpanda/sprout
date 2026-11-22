import SwiftUI

/// Dot-matrix palette: ink, plus LED colours that each mean one thing.
/// Orange = bytes coming in, green = bytes going out (the sprout giving back), amber = waiting or
/// checking, red = errors. Shape still tells direction (solid in, rings out), so colour is never the only cue.
extension Color {
    /// Window ground: black in dark mode, neutral paper in light mode.
    static let ground = Color("Ground")
    /// A band that sits on the ground (pulse band).
    static let raised = Color("Raised")
    /// A lit dot.
    static let lit = Color("Lit")
    /// An unlit dot, faintly visible like an LED panel.
    static let unlit = Color("Unlit")
    /// International Orange: bytes are coming in right now. Never decoration, never selection.
    static let signal = Color("Signal")
    /// Sprout green: bytes are going out (seeding). The upload half of the LED pair.
    static let growth = Color("Growth")
    /// Amber: waiting, queued or checking. Something will happen, nothing is moving yet.
    static let caution = Color("Caution")
    /// Errors only, always next to a word.
    static let fault = Color("Fault")
    /// The default button in sheets and dialogs: dark graphite under white text, the way macOS
    /// draws a monochrome default button. The app accent (AccentColor) is lighter, because macOS
    /// also uses it as the text colour of selected tabs.
    static let action = Color(nsColor: NSColor(name: "SproutAction") { appearance in
        NSColor(white: appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? 0.40 : 0.30, alpha: 1)
    })
}

extension Torrent {
    // A finished torrent's stray download bytes don't count: the row doesn't show them either.
    var isMoving: Bool { (downloadSpeed >= Format.movingThreshold && progress < 1) || uploadSpeed >= Format.movingThreshold }

    var isFetching: Bool { downloadSpeed >= Format.movingThreshold && progress < 1 }
    var isGiving: Bool { uploadSpeed >= Format.movingThreshold }

    /// Colour for this torrent's big number: orange while bytes come in (download wins when both
    /// move), green while it only gives back, ink otherwise.
    var figureColor: Color {
        if state.isError { return .fault }
        if isFetching { return .signal }
        if isGiving { return .growth }
        return state.isStopped ? .secondary : .lit
    }
}

extension TorrentState {
    /// The state's LED colour, for its icon. Dots and digits colour only while bytes move;
    /// a state icon keeps its colour because it names the state, not the traffic.
    var tint: Color {
        switch self {
        case .downloading, .forcedDL, .metaDL, .forcedMetaDL: .signal
        case .uploading, .forcedUP, .stalledUP: .growth
        case .stalledDL, .queuedDL, .queuedUP, .checkingDL, .checkingUP, .checkingResumeData, .allocating, .moving: .caution
        case .error, .missingFiles: .fault
        case .stoppedUP: .lit
        case .stoppedDL, .unknown: .secondary
        }
    }
}

/// Haptics on a Force Touch trackpad. They only play while a finger is on the trackpad, so they
/// answer direct actions (a drop landing, a toggle), never background events.
enum Haptic {
    static func tap() { NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now) }
    static func step() { NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now) }
}

/// A text link in ink, not the system blue. A dotted underline (the world's dot) marks it as
/// clickable at rest; it turns solid under the pointer and dims while pressed.
struct InkLinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        InkLink(configuration: configuration)
    }

    private struct InkLink: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(Color.primary)
                .underline(true, pattern: hovering ? .solid : .dot)
                .opacity(configuration.isPressed ? 0.55 : 1)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}

extension ButtonStyle where Self == InkLinkButtonStyle {
    static var inkLink: InkLinkButtonStyle { InkLinkButtonStyle() }
}

/// A checkbox drawn in ink. The system's unchecked box is dark grey on dark grey, which
/// vanished on Sprout's black ground; this one keeps an outline you can see when it's off.
struct InkCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 3.5)
                    .fill(configuration.isOn ? Color.lit : Color.clear)
                RoundedRectangle(cornerRadius: 3.5)
                    .strokeBorder(configuration.isOn ? Color.lit : Color.secondary, lineWidth: 1.25)
                if configuration.isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(Color.ground)
                }
            }
            .frame(width: 14, height: 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // VoiceOver hears a plain checkbox with the toggle's own label.
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}

extension ToggleStyle where Self == InkCheckboxStyle {
    static var inkCheckbox: InkCheckboxStyle { InkCheckboxStyle() }
}
