import AppKit

/// Publishes what's playing anywhere on the Mac (browsers, web apps, Music, Spotify…) and sends media commands.
///
/// Several apps can have something loaded at once. The player row shows one of them (`info`): the one
/// the user picked, or else the one that's playing. Commands reach it by the most reliable route.
@Observable
final class NowPlayingMonitor {
    /// Every app with something loaded.
    private(set) var players: [NowPlayingInfo] = []
    /// macOS's "now playing" pick: media keys and system commands go to it.
    private(set) var electedID: String?
    /// The player the user chose in the switcher; cleared when another app starts playing.
    private(set) var selectedID: String?

    /// The player the notch shows and controls.
    var info: NowPlayingInfo? {
        if let selectedID, let chosen = players.first(where: { $0.id == selectedID }) { return chosen }
        return Self.preferred(in: players, electedID: electedID)
    }

    /// With nothing chosen: macOS's pick if it's playing, else anything playing, else the pick, else any.
    static func preferred(in players: [NowPlayingInfo], electedID: String?) -> NowPlayingInfo? {
        let elected = players.first { $0.id == electedID }
        if let elected, elected.isPlaying { return elected }
        return players.first(where: \.isPlaying) ?? elected ?? players.first
    }

    /// How a command reaches a player.
    enum ControlRoute: Equatable {
        /// macOS's pick: the system media command.
        case system
        /// Another app that takes AppleScript (Spotify, Music).
        case script
        /// Can't be reached reliably from here: offer to open the app instead of guessing.
        case openApp
    }

    func route(for player: NowPlayingInfo) -> ControlRoute {
        if player.id == electedID { return .system }
        if NowPlayingScripting.supports(player.appBundleIdentifier) { return .script }
        return .openApp
    }

    /// Runs AppleScript; replaceable in tests.
    @ObservationIgnored var runScript: (String) -> Bool = NowPlayingScripting.run
    /// Brings an app forward; replaceable in tests.
    @ObservationIgnored var openApp: (String) -> Void = { bundleIdentifier in
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
    /// The app you're using right now; while it's the one playing, the notch doesn't repeat it.
    private(set) var frontmostAppBundleIdentifier: String?

    /// True while the playing app is the frontmost one.
    var isSourceInFront: Bool {
        info?.isFrom(app: frontmostAppBundleIdentifier) == true
    }

    @ObservationIgnored var onTrackChanged: ((NowPlayingInfo) -> Void)?

    @ObservationIgnored private let bridge = NowPlayingBridgeProcess()
    @ObservationIgnored private var restartTask: Task<Void, Never>?
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var activationObserver: NSObjectProtocol?

    /// Started explicitly by the app (not in init) so tests and previews don't spawn processes.
    func start(libraryURL: URL? = NowPlayingBridgeProcess.defaultLibraryURL) {
        guard !isStarted, let libraryURL else { return }
        isStarted = true

        bridge.onUpdate = { [weak self] snapshot in
            self?.receive(snapshot ?? .empty)
        }
        watchFrontmostApp()
        bridge.onExit = { [weak self] in
            self?.scheduleRestart(libraryURL: libraryURL)
        }
        try? bridge.start(libraryURL: libraryURL)
    }

    func stop() {
        isStarted = false
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        restartTask?.cancel()
        bridge.onExit = nil
        bridge.stop()
        receive(.empty)
    }

    /// A report from the bridge. Announces a new track, unless you're already looking at its app.
    func receive(_ snapshot: NowPlayingSnapshot) {
        let previous = info
        let wasPlaying = Set(players.filter(\.isPlaying).map(\.id))
        players = snapshot.players
        electedID = snapshot.electedID

        // Another app starting to play takes over the row again; a vanished choice is forgotten.
        let startedPlaying = players.filter { $0.isPlaying && !wasPlaying.contains($0.id) }.map(\.id)
        if let selectedID, startedPlaying.contains(where: { $0 != selectedID }) || !players.contains(where: { $0.id == selectedID }) {
            self.selectedID = nil
        }

        if let info, info.isNewTrack(after: previous), !isSourceInFront {
            onTrackChanged?(info)
        }
    }

    func frontmostAppChanged(to bundleIdentifier: String?) {
        frontmostAppBundleIdentifier = bundleIdentifier
    }

    /// Follows app switches through NSWorkspace's notification: event-driven, no polling.
    private func watchFrontmostApp() {
        frontmostAppChanged(to: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleIdentifier = app?.bundleIdentifier
            MainActor.assumeIsolated {
                self?.frontmostAppChanged(to: bundleIdentifier)
            }
        }
    }

    /// Sends a command to the player the row shows.
    func send(_ command: NowPlayingBridgeProcess.Command) {
        guard let info else { return }
        send(command, to: info)
    }

    func send(_ command: NowPlayingBridgeProcess.Command, to player: NowPlayingInfo) {
        switch route(for: player) {
        case .system:
            bridge.send(command)
        case .script:
            guard let source = NowPlayingScripting.source(for: command, in: player.appBundleIdentifier),
                  runScript(source)
            else {
                openApp(player.appBundleIdentifier)   // permission declined or the app didn't answer
                return
            }
        case .openApp:
            openApp(player.appBundleIdentifier)
        }
    }

    /// The user picked a player in the switcher.
    func select(_ player: NowPlayingInfo) {
        selectedID = player.id
    }

    /// Seeks the shown player to `position` seconds, using the best route for that player.
    func seek(to position: TimeInterval) {
        guard let info else { return }
        switch route(for: info) {
        case .system:
            bridge.sendSeek(to: position)
        case .script:
            if let source = NowPlayingScripting.seekSource(to: position, in: info.appBundleIdentifier) {
                _ = runScript(source)
            }
        case .openApp:
            break   // can't seek a player we can't reach
        }
    }

    /// If the bridge dies (e.g. a macOS update breaks it), try again after a pause instead of spinning.
    private func scheduleRestart(libraryURL: URL) {
        guard isStarted else { return }
        receive(.empty)
        restartTask?.cancel()
        restartTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, let self, self.isStarted else { return }
            try? self.bridge.start(libraryURL: libraryURL)
        }
    }
}
