import Foundation
import Testing
@testable import Notch

@MainActor
struct NowPlayingMonitorTests {
    private func info(_ title: String = "Song", app: String = "com.music", isPlaying: Bool = true) -> NowPlayingInfo {
        NowPlayingInfo(title: title, artist: "Artist", album: "", duration: 200, elapsedTime: 0,
                       playbackRate: 1, timestamp: .now, isPlaying: isPlaying,
                       appName: "Music", appBundleIdentifier: app)
    }

    @Test func claimsTheEarsWhilePlayingInAnotherApp() {
        let monitor = NowPlayingMonitor()
        monitor.frontmostAppChanged(to: "com.editor")
        monitor.receive(.only(info()))
        #expect(monitor.earPriority == 3)
    }

    @Test func stepsAsideWhileThePlayingAppIsInFront() {
        let monitor = NowPlayingMonitor()
        monitor.receive(.only(info(app: "com.music")))
        monitor.frontmostAppChanged(to: "com.music")
        #expect(monitor.isSourceInFront)
        #expect(monitor.earPriority == nil)

        monitor.frontmostAppChanged(to: "com.editor")
        #expect(monitor.earPriority == 3, "switching away brings the ears back")
    }

    @Test func thePlayerRowStaysWhileThePlayingAppIsInFront() {
        let monitor = NowPlayingMonitor()
        monitor.frontmostAppChanged(to: "com.music")
        monitor.receive(.only(info(app: "com.music")))
        #expect(monitor.hasHeadline)
    }

    @Test func announcesANewTrackFromAnotherApp() {
        let monitor = NowPlayingMonitor()
        var announced: [String] = []
        monitor.onTrackChanged = { announced.append($0.title) }
        monitor.frontmostAppChanged(to: "com.editor")

        monitor.receive(.only(info("One")))
        monitor.receive(.only(info("Two")))
        #expect(announced == ["Two"])
    }

    @Test func staysQuietAboutANewTrackInTheAppYoureUsing() {
        let monitor = NowPlayingMonitor()
        var announced: [String] = []
        monitor.onTrackChanged = { announced.append($0.title) }
        monitor.frontmostAppChanged(to: "com.music")

        monitor.receive(.only(info("One")))
        monitor.receive(.only(info("Two")))
        #expect(announced.isEmpty)
    }

    @Test func nothingPlayingIsNeverInFront() {
        let monitor = NowPlayingMonitor()
        monitor.frontmostAppChanged(to: "com.music")
        #expect(!monitor.isSourceInFront)
        #expect(monitor.earPriority == nil)
    }
}

extension NowPlayingSnapshot {
    /// One app with a track, which is also macOS's pick.
    static func only(_ player: NowPlayingInfo) -> NowPlayingSnapshot {
        NowPlayingSnapshot(players: [player], electedID: player.id)
    }
}

@MainActor
struct SeveralPlayersTests {
    private func player(_ app: String, _ title: String = "Song", playing: Bool = false) -> NowPlayingInfo {
        NowPlayingInfo(title: title, artist: "Artist", album: "", duration: 200, elapsedTime: 0,
                       playbackRate: playing ? 1 : 0, timestamp: .now, isPlaying: playing,
                       appName: app, appBundleIdentifier: app)
    }

    private let web = "com.apple.Safari.WebApp.X"
    private let spotify = "com.spotify.client"

    @Test func showsMacOSsPickWhenItsPlaying() {
        let monitor = NowPlayingMonitor()
        monitor.receive(NowPlayingSnapshot(players: [player(spotify, playing: true), player(web, playing: true)], electedID: web))
        #expect(monitor.info?.id == web)
    }

    @Test func showsWhateverIsPlayingOverAPausedPick() {
        let monitor = NowPlayingMonitor()
        monitor.receive(NowPlayingSnapshot(players: [player(spotify, playing: true), player(web)], electedID: web))
        #expect(monitor.info?.id == spotify)
    }

    @Test func showsThePickWhenNothingPlays() {
        let monitor = NowPlayingMonitor()
        monitor.receive(NowPlayingSnapshot(players: [player(spotify), player(web)], electedID: web))
        #expect(monitor.info?.id == web)
    }

    @Test func aChosenPlayerStaysShown() {
        let monitor = NowPlayingMonitor()
        let snapshot = NowPlayingSnapshot(players: [player(spotify), player(web, playing: true)], electedID: web)
        monitor.receive(snapshot)
        monitor.select(player(spotify))
        #expect(monitor.info?.id == spotify)
        monitor.receive(snapshot)
        #expect(monitor.info?.id == spotify, "updates don't undo the choice")
    }

    @Test func anotherAppStartingToPlayTakesOverAgain() {
        let monitor = NowPlayingMonitor()
        monitor.receive(NowPlayingSnapshot(players: [player(spotify), player(web)], electedID: web))
        monitor.select(player(spotify))
        monitor.receive(NowPlayingSnapshot(players: [player(spotify), player(web, playing: true)], electedID: web))
        #expect(monitor.selectedID == nil)
        #expect(monitor.info?.id == web)
    }

    @Test func theChosenAppStartingToPlayKeepsTheChoice() {
        let monitor = NowPlayingMonitor()
        monitor.receive(NowPlayingSnapshot(players: [player(spotify), player(web)], electedID: web))
        monitor.select(player(spotify))
        monitor.receive(NowPlayingSnapshot(players: [player(spotify, playing: true), player(web)], electedID: web))
        #expect(monitor.info?.id == spotify)
    }

    @Test func aChosenAppThatGoesAwayIsForgotten() {
        let monitor = NowPlayingMonitor()
        monitor.receive(NowPlayingSnapshot(players: [player(spotify), player(web)], electedID: web))
        monitor.select(player(spotify))
        monitor.receive(.only(player(web)))
        #expect(monitor.selectedID == nil)
        #expect(monitor.info?.id == web)
    }

    @Test func switchingPlayersIsNotANewTrack() {
        let monitor = NowPlayingMonitor()
        var announced: [String] = []
        monitor.onTrackChanged = { announced.append($0.title) }
        let snapshot = NowPlayingSnapshot(players: [player(spotify, "A", playing: true), player(web, "B", playing: true)], electedID: web)
        monitor.receive(snapshot)
        monitor.select(player(spotify))
        monitor.receive(snapshot)
        #expect(announced.isEmpty)
    }

    // MARK: - Routing

    @Test func routesByHowEachPlayerCanBeReached() {
        let monitor = NowPlayingMonitor()
        monitor.receive(NowPlayingSnapshot(players: [player(spotify), player(web), player("com.apple.Music")], electedID: web))
        #expect(monitor.route(for: player(web)) == .system, "macOS's pick")
        #expect(monitor.route(for: player(spotify)) == .script)
        #expect(monitor.route(for: player("com.apple.Music")) == .script)
        #expect(monitor.route(for: player("com.google.Chrome")) == .openApp)
    }

    @Test func aScriptableAppGetsItsScript() {
        let monitor = NowPlayingMonitor()
        var scripts: [String] = []
        monitor.runScript = { scripts.append($0); return true }
        monitor.receive(NowPlayingSnapshot(players: [player(spotify), player(web)], electedID: web))
        monitor.send(.toggle, to: player(spotify))
        monitor.send(.next, to: player(spotify))
        #expect(scripts == [#"tell application id "com.spotify.client" to playpause"#,
                            #"tell application id "com.spotify.client" to next track"#])
    }

    @Test func aDeclinedScriptOpensTheAppInstead() {
        let monitor = NowPlayingMonitor()
        var opened: [String] = []
        monitor.runScript = { _ in false }
        monitor.openApp = { opened.append($0) }
        monitor.receive(NowPlayingSnapshot(players: [player(spotify), player(web)], electedID: web))
        monitor.send(.toggle, to: player(spotify))
        #expect(opened == [spotify])
    }

    @Test func anUnreachablePlayerOpensItsApp() {
        let monitor = NowPlayingMonitor()
        var opened: [String] = []
        var scripts = 0
        monitor.openApp = { opened.append($0) }
        monitor.runScript = { _ in scripts += 1; return true }
        monitor.receive(NowPlayingSnapshot(players: [player(spotify), player(web)], electedID: spotify))
        monitor.send(.toggle, to: player(web))
        #expect(opened == [web])
        #expect(scripts == 0, "never a command that could reach another app")
    }

    @Test func seekingScriptablePlayerExecutesAppleScript() {
        let monitor = NowPlayingMonitor()
        var scripts: [String] = []
        monitor.runScript = { scripts.append($0); return true }
        monitor.receive(NowPlayingSnapshot(players: [player(spotify), player(web)], electedID: web))
        monitor.select(player(spotify))
        monitor.seek(to: 120.5)
        #expect(scripts == [#"tell application id "com.spotify.client" to set player position to 120.5"#])
    }

    @Test func seekingUnreachablePlayerDoesNotExecuteScriptOrOpenApp() {
        let monitor = NowPlayingMonitor()
        var opened: [String] = []
        var scripts: [String] = []
        monitor.openApp = { opened.append($0) }
        monitor.runScript = { scripts.append($0); return true }
        monitor.receive(NowPlayingSnapshot(players: [player(web)], electedID: spotify))
        monitor.seek(to: 60)
        #expect(opened.isEmpty)
        #expect(scripts.isEmpty)
    }

    @Test func seekSourceGeneratesScriptForSupportedApps() {
        #expect(NowPlayingScripting.seekSource(to: 45.0, in: "com.spotify.client") == #"tell application id "com.spotify.client" to set player position to 45.0"#)
        #expect(NowPlayingScripting.seekSource(to: 30.0, in: "com.apple.Music") == #"tell application id "com.apple.Music" to set player position to 30.0"#)
        #expect(NowPlayingScripting.seekSource(to: 15.0, in: "com.google.Chrome") == nil)
    }
}
