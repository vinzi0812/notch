import SwiftUI

extension NowPlayingMonitor: NotchModule {
    var feature: NotchFeature { .nowPlaying }

    /// Above the battery (0), below an imminent meeting (5) and a running timer (10), only while
    /// playing, and not while you're in the playing app (the ears would just repeat what's on screen).
    var earPriority: Int? {
        info?.isPlaying == true && !isSourceInFront ? 3 : nil
    }


    /// Shown whenever there's something to control, playing or paused.
    var hasHeadline: Bool { info != nil }

    @ViewBuilder
    func content(for placement: NotchPlacement) -> some View {
        if let info {
            switch placement {
            case .leadingEar, .pill:
                if info.isFromBrowser {
                    Image(systemName: "music.note")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 16, height: 16)
                } else {
                    SourceAppIcon(bundleIdentifier: info.appBundleIdentifier)
                        .frame(width: 16, height: 16)
                }
            case .trailingEar:
                PlayingIndicator(isPlaying: info.isPlaying)
            case .headline:
                PlayerRow(monitor: self, info: info)
            case .activityLeading:
                ArtworkTile(info: info)
                    .frame(width: 26, height: 26)
            case .activityTrailing:
                PlayingIndicator(isPlaying: info.isPlaying)
                    .font(.title3)
            case .activityDetail:
                Text([info.title, info.artist].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .lineLimit(1)
                    .padding(.horizontal, 16)
            case .page:
                EmptyView()
            }
        }
    }
}

/// Artwork-sized app icon, title, artist, live progress, and transport controls. With several apps
/// holding a track, their icons appear on the right to switch which one the row shows and controls.
private struct PlayerRow: View {
    let monitor: NowPlayingMonitor
    let info: NowPlayingInfo

    private var canSeek: Bool {
        monitor.route(for: info) != .openApp
    }

    var body: some View {
        HStack(spacing: 12) {
            ArtworkTile(info: info)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(info.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text([info.artist, info.appName].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                if info.duration > 0 {
                    PlaybackProgress(info: info, monitor: monitor, canSeek: canSeek)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            controls
                .buttonStyle(.plain)

            if monitor.players.count > 1 {
                PlayerSwitcher(monitor: monitor, shown: info)
            }
        }
        .animation(.snappy, value: info.isPlaying)
        .animation(.snappy, value: info.id)
    }

    @ViewBuilder
    private var controls: some View {
        if monitor.route(for: info) == .openApp {
            // This player only takes commands while it's the Mac's current player, so rather than send
            // one that might reach another app, offer the app itself.
            Button {
                monitor.send(.toggle, to: info)
            } label: {
                Label("Open", systemImage: "arrow.up.forward.app")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .glassControl(in: Capsule())
            }
            .help("\(info.appName) can be controlled here while it's the Mac's current player. Open it to play or pause.")
        } else {
            HStack(spacing: 8) {
                control("backward.fill", .previous)
                control(info.isPlaying ? "pause.fill" : "play.fill", .toggle)
                    .contentTransition(.symbolEffect(.replace))
                control("forward.fill", .next)
            }
        }
    }

    private func control(_ symbol: String, _ command: NowPlayingBridgeProcess.Command) -> some View {
        Button {
            monitor.send(command, to: info)
        } label: {
            Image(systemName: symbol)
                .frame(width: 28, height: 28)
                .glassControl(in: Circle())
        }
    }
}

/// The apps holding a track, as small icons. The shown one is lit; a playing one has a dot.
private struct PlayerSwitcher: View {
    let monitor: NowPlayingMonitor
    let shown: NowPlayingInfo
    @Namespace private var selection

    var body: some View {
        HStack(spacing: 4) {
            ForEach(monitor.players) { player in
                let isShown = player.id == shown.id
                Button {
                    monitor.select(player)
                } label: {
                    SourceAppIcon(bundleIdentifier: player.appBundleIdentifier)
                        .frame(width: 20, height: 20)
                        .padding(4)
                        .background {
                            if isShown {
                                Color.clear.matchedGeometryEffect(id: "shown-player", in: selection)
                            }
                        }
                        .opacity(isShown ? 1 : 0.5)
                        .overlay(alignment: .bottom) {
                            if player.isPlaying {
                                Circle().fill(.white).frame(width: 3, height: 3).offset(y: 3)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help([player.appName, player.title].filter { !$0.isEmpty }.joined(separator: " · "))
            }
        }
        .background {
            // One glass square behind the icons that slides to whichever app is shown.
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.clear)
                .glassSurface(in: .rect(cornerRadius: 7, style: .continuous), fallbackOpacity: 0.2)
                .matchedGeometryEffect(id: "shown-player", in: selection, isSource: false)
        }
        .animation(.snappy, value: shown.id)
        .padding(.leading, 4)
        .overlay(alignment: .leading) {
            Rectangle().fill(.white.opacity(0.15)).frame(width: 1, height: 24).offset(x: -6)
        }
    }
}

/// A thin progress line with elapsed and remaining time. Tap or drag the bar to seek.
private struct PlaybackProgress: View {
    let info: NowPlayingInfo
    let monitor: NowPlayingMonitor
    let canSeek: Bool
    @Environment(\.notchAccent) private var accent
    @State private var isDragging = false
    @State private var dragFraction: CGFloat?
    /// Holds the seek position after release so the bar doesn't snap back before the player updates.
    @State private var seekedFraction: CGFloat?
    @State private var seekHoldTask: Task<Void, Never>?
    @State private var isHovering = false

    /// The fraction to display, choosing the most specific override available.
    private func activeFraction(live: CGFloat) -> CGFloat {
        dragFraction ?? seekedFraction ?? live
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = info.elapsed(at: context.date)
            let liveFraction = info.duration > 0 ? elapsed / info.duration : 0
            let fraction = activeFraction(live: liveFraction)
            let displayElapsed = fraction * info.duration
            HStack(spacing: 6) {
                Text(Self.format(displayElapsed))
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(0.25))
                        Capsule()
                            .fill(accent)
                            .frame(width: proxy.size.width * min(1, max(0, fraction)))
                    }
                    .contentShape(Rectangle())
                    .if(canSeek) { view in
                        view.gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    isDragging = true
                                    seekHoldTask?.cancel()
                                    let newFraction = min(1, max(0, value.location.x / proxy.size.width))
                                    // Instant feedback while scrubbing — no animation delay.
                                    dragFraction = newFraction
                                    seekedFraction = nil
                                }
                                .onEnded { value in
                                    let finalFraction = min(1, max(0, value.location.x / proxy.size.width))
                                    let seekPosition = finalFraction * info.duration
                                    monitor.seek(to: seekPosition)
                                    // Slide the bar to the tapped position.
                                    withAnimation(.smooth(duration: 0.3)) {
                                        dragFraction = nil
                                        seekedFraction = finalFraction
                                        isDragging = false
                                    }
                                    // Hold until the player reports back, then fade out smoothly.
                                    seekHoldTask?.cancel()
                                    seekHoldTask = Task {
                                        try? await Task.sleep(for: .seconds(2.5))
                                        guard !Task.isCancelled else { return }
                                        withAnimation(.smooth(duration: 0.4)) {
                                            seekedFraction = nil
                                        }
                                    }
                                }
                        )
                    }
                }
                .frame(height: canSeek && (isHovering || isDragging) ? 6 : 3)
                .animation(.easeOut(duration: 0.15), value: canSeek && isHovering)
                .animation(.easeOut(duration: 0.15), value: canSeek && isDragging)
                .onHover { hovering in if canSeek { isHovering = hovering } }
                Text("-" + Self.format(info.duration - displayElapsed))
            }
            .font(.system(size: 9).monospacedDigit())
            .foregroundStyle(.white.opacity(0.6))
            // Suppress animation on every 1-second timeline tick so the bar doesn't jitter.
            .transaction { $0.animation = nil }
        }
    }

    private static func format(_ seconds: TimeInterval) -> String {
        Duration.seconds(Int(max(0, seconds))).formatted(.time(pattern: .minuteSecond))
    }
}

private extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

/// Stands in for album art, which third-party apps can't read: the playing app's icon on a soft
/// background tinted with the icon's own colors, the way Apple's media controls look without art.
/// For a browser, a music note in the accent color instead, since the browser isn't what's playing.
private struct ArtworkTile: View {
    let info: NowPlayingInfo
    @Environment(\.notchAccent) private var accent

    private var bundleIdentifier: String { info.appBundleIdentifier }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            if info.isFromBrowser {
                RoundedRectangle(cornerRadius: side * 0.22, style: .continuous)
                    .fill(LinearGradient(colors: [accent.opacity(0.9), accent.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: side * 0.45, weight: .semibold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.25), radius: side * 0.05, y: side * 0.03)
                    }
            } else {
                appTile(side: side)
            }
        }
    }

    private func appTile(side: CGFloat) -> some View {
        Group {
            let tint = Color(nsColor: AppIconTint.color(for: bundleIdentifier))
            RoundedRectangle(cornerRadius: side * 0.22, style: .continuous)
                .fill(LinearGradient(colors: [tint.opacity(0.95), tint.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    SourceAppIcon(bundleIdentifier: bundleIdentifier)
                        .frame(width: side * 0.68, height: side * 0.68)
                        .shadow(color: .black.opacity(0.3), radius: side * 0.05, y: side * 0.03)
                }
        }
    }
}

/// Remembers each app's icon tint so it's computed once, not on every redraw.
private enum AppIconTint {
    static var cache: [String: NSColor] = [:]

    static func color(for bundleIdentifier: String) -> NSColor {
        if let cached = cache[bundleIdentifier] { return cached }
        let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
        let color = icon?.averageColor ?? .darkGray
        cache[bundleIdentifier] = color
        return color
    }
}

/// The icon of the app that's playing (e.g. the YouTube Music web app), or a note if it can't be found.
private struct SourceAppIcon: View {
    let bundleIdentifier: String

    var body: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
        } else {
            Image(systemName: "music.note")
        }
    }
}

/// Animated bars while playing; still while paused.
private struct PlayingIndicator: View {
    let isPlaying: Bool

    var body: some View {
        Image(systemName: "waveform")
            .symbolEffect(.variableColor.iterative, isActive: isPlaying)
            .foregroundStyle(.white.opacity(isPlaying ? 1 : 0.5))
    }
}
