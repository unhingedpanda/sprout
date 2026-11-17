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
