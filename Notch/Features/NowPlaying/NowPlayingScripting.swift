import Foundation

/// Plays, pauses and skips in apps that take AppleScript commands, for players that aren't macOS's
/// "now playing" pick (system media commands only reach that one reliably).
///
/// Sandboxed, the app may only send Apple events to the apps listed in its entitlements
/// (`com.apple.security.temporary-exception.apple-events`), and macOS asks the user once per app.
enum NowPlayingScripting {
    /// Apps with a scripting dictionary that includes playpause / next track / previous track.
    static let scriptableApps: Set<String> = ["com.spotify.client", "com.apple.Music"]

    static func supports(_ bundleIdentifier: String) -> Bool {
        scriptableApps.contains(bundleIdentifier)
    }

    /// The AppleScript for `command` in the app, or nil if the app isn't scriptable.
    static func source(for command: NowPlayingBridgeProcess.Command, in bundleIdentifier: String) -> String? {
        guard supports(bundleIdentifier) else { return nil }
        let verb = switch command {
        case .toggle: "playpause"
        case .next: "next track"
        case .previous: "previous track"
        }
        return "tell application id \"\(bundleIdentifier)\" to \(verb)"
    }

    /// Runs the script. False if it failed, e.g. the user declined the permission prompt.
    nonisolated static func run(_ source: String) -> Bool {
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil
    }

    /// The AppleScript to seek to `position` seconds in the app, or nil if the app isn't scriptable.
    static func seekSource(to position: TimeInterval, in bundleIdentifier: String) -> String? {
        guard supports(bundleIdentifier) else { return nil }
        return "tell application id \"\(bundleIdentifier)\" to set player position to \(position)"
    }
}
