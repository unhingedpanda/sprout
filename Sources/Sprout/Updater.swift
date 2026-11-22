import AppKit
import Sparkle

/// Sparkle: the feed URL and EdDSA public key are in Info.plist. It checks on its own once a
/// day; the app menu's "Check for Updates…" asks now.
@MainActor
final class Updater {
    static let shared = Updater()
    private let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
