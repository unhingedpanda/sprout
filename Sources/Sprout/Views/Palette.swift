import SwiftUI

/// Dot-matrix palette. Monochrome ink plus one signal colour that only ever means "data moving".
extension Color {
    /// Window ground: black in dark mode, neutral paper in light mode.
    static let ground = Color("Ground")
    /// A band that sits on the ground (pulse band).
    static let raised = Color("Raised")
    /// A lit dot.
    static let lit = Color("Lit")
    /// An unlit dot, faintly visible like an LED panel.
    static let unlit = Color("Unlit")
    /// International Orange: bytes are moving right now. Never decoration, never selection.
    static let signal = Color("Signal")
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
    var isMoving: Bool { downloadSpeed >= Format.movingThreshold || uploadSpeed >= Format.movingThreshold }

    /// Colour for this torrent's big number: orange while moving, ink otherwise.
    var figureColor: Color {
        if state.isError { return .fault }
        if isMoving { return .signal }
        return state.isStopped ? .secondary : .lit
    }
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
