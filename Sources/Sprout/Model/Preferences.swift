import Foundation

/// Sprout's own settings. Engine settings live in the engine and are edited through its API.
enum Preferences {
    static let notifyOnCompletionKey = "NotifyOnCompletion"
    static let preventSleepKey = "PreventSleepWhileDownloading"

    static var notifyOnCompletion: Bool { UserDefaults.standard.object(forKey: notifyOnCompletionKey) as? Bool ?? true }
    static var preventSleep: Bool { UserDefaults.standard.object(forKey: preventSleepKey) as? Bool ?? true }
}
