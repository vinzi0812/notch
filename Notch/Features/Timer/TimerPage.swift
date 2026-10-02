import AppKit
import SwiftUI

/// The timer's full-width page. While idle: a ruler to pick the length, "Start Timer", and the
/// chosen time. While running or paused: the countdown with pause/resume and cancel.
struct TimerPage: View {
    let timer: TimerController

    @Environment(\.notchAccent) private var accent
    @Environment(\.timerPresets) private var presets

    var body: some View {
        Group {
            if timer.state.phase == .idle {
                picker
            } else {
                running
            }
        }
        .animation(.smooth(duration: 0.4), value: timer.state.phase == .idle)
    }

    private var duration: Binding<TimeInterval> {
        Binding(get: { timer.duration }, set: { timer.setDuration(seconds: $0) })
    }

    private var picker: some View {
        VStack(spacing: 14) {
            DurationRuler(seconds: duration)
                .frame(height: 76)

            HStack(alignment: .center) {
                Button {
                    timer.start()
                } label: {
                    Text("Start Timer")
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(accent)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .glassControl(in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)

                // The chips give way first when space is short (a narrow notch, an hour-long time):
                // ViewThatFits shows the first layout that fits, so 4 chips, then 3, 2, or none.
                ViewThatFits(in: .horizontal) {
                    ForEach([4, 3, 2], id: \.self) { count in
                        HStack(spacing: 0) {
                            Spacer(minLength: 12)
                            presetChips(count: count)
                            Spacer(minLength: 12)
                        }
                    }
                    Spacer(minLength: 12)
                }

                Text(TimerFormat.string(seconds: Int(timer.duration)))
                    .font(.system(size: 40, weight: .light))
                    .fixedSize()
                    .monospacedDigit()
                    .foregroundStyle(accent)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: timer.duration)
            }
        }
        .transition(.opacity)
    }

    /// One-tap lengths between "Start Timer" and the time. Tapping one moves the ruler to it.
    private func presetChips(count: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(presets.prefix(count).enumerated()), id: \.offset) { _, seconds in
                let isCurrent = timer.duration == seconds
                Button {
                    timer.setDuration(seconds: seconds)
                } label: {
                    Text(Self.chipTitle(seconds: seconds))
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(isCurrent ? .black : accent)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background {
                            // The chosen length is solid accent; the others are glass.
                            if isCurrent { Capsule().fill(accent) }
                        }
                        .glassControl(in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .animation(.snappy, value: isCurrent)
            }
        }
        .fixedSize()
    }

    /// "5m", "45m", "1h", "1h30".
    static func chipTitle(seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        guard minutes >= 60 else { return "\(minutes)m" }
        let rest = minutes % 60
        return rest == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h\(String(format: "%02d", rest))"
    }

    /// Mirrors the picker: controls on the left where "Start Timer" was, the time on the right where it was chosen.
    private var running: some View {
        HStack(spacing: 20) {
            HStack(spacing: 12) {
                roundButton(timer.isRunning ? "pause.fill" : "play.fill") { timer.toggle() }
                roundButton("xmark") { timer.reset() }
            }
            .buttonStyle(.plain)

            Spacer()

            Countdown(timer: timer)
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(accent)
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
        .transition(.opacity)
    }

    private func roundButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(accent)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 46, height: 46)
                .glassControl(in: Circle())
                .contentShape(Circle())
        }
    }
}

/// A ruler of minutes under a fixed pointer, like the iOS timer picker: a tick per minute, numbers
/// every five, ticks up to the selection bright and the rest dim, both ends fading out.
///
/// Its position is a continuous value in seconds, so it follows the hand exactly while dragging or
/// scrolling; the selection is that value snapped to a step, and the ruler springs to it on release.
/// Click and hold for half a second to zoom in 4× and choose in 15-second steps.
struct DurationRuler: View {
    @Environment(\.notchAccent) private var accent
    @Environment(\.hapticFeedbackEnabled) private var hapticEnabled
    @Binding var seconds: TimeInterval

    /// The ruler shows 0 so the scale reads naturally, but 0 can't be chosen.
    static let visibleRange: ClosedRange<TimeInterval> = 0...TimerState.durationRange.upperBound
    static let tickSpacing: CGFloat = 15
    static let fineHoldDuration: Duration = .milliseconds(500)

    /// Continuous position under the pointer, in seconds.
    @State private var position: TimeInterval = 0
    /// How zoomed in the ruler looks. Visual only.
    @State private var isFine = false
    /// How precisely it selects: 60 s normally, 15 s after a click-and-hold. Kept separate from the zoom,
    /// so zooming back out never rounds away a 15-second value; a new normal interaction resets it.
    @State private var step: TimeInterval = 60
    @State private var dragStart: TimeInterval?
    @State private var dragStartLocation: CGPoint?
    @State private var holdTask: Task<Void, Never>?
    @State private var isScrolling = false
    @State private var isHovering = false
    @State private var scrollMonitor: Any?
    @State private var glowingSeconds: TimeInterval?
    @State private var glowAmount: Double = 0
    @State private var glowTask: Task<Void, Never>?

    // MARK: Math (pure, tested)

    /// Horizontal points per second of duration: a minute is one tick apart, or four in fine mode.
    static func pointsPerSecond(fine: Bool) -> CGFloat {
        fine ? tickSpacing / 15 : tickSpacing / 60
    }

    /// The choosable value nearest a position, in steps of `step` (60 s, or 15 s for fine choices).
    static func snapped(_ position: TimeInterval, step: TimeInterval) -> TimeInterval {
        let value = (position / step).rounded() * step
        return min(max(value, step), TimerState.durationRange.upperBound)
    }

    /// The precision a value needs to be shown as-is: 15-second steps unless it's a whole minute.
    static func step(for value: TimeInterval) -> TimeInterval {
        value.truncatingRemainder(dividingBy: 60) == 0 ? 60 : 15
    }

    /// Past either end the ruler still moves, but with resistance, like an iOS scroll view.
    static func rubberBanded(_ position: TimeInterval) -> TimeInterval {
        let upper = visibleRange.upperBound
        if position < 0 { return position * 0.3 }
        if position > upper { return upper + (position - upper) * 0.3 }
        return position
    }

    // MARK: View

    private var pointsPerSecond: CGFloat { Self.pointsPerSecond(fine: isFine) }
    private var selection: TimeInterval { Self.snapped(position, step: step) }

    var body: some View {
        GeometryReader { proxy in
            RulerCanvas(
                accent: accent,
                position: position,
                pointsPerSecond: Double(pointsPerSecond),
                glow: glowAmount,
                glowingSeconds: glowingSeconds,
                selection: selection
            )
            .mask {
                LinearGradient(
                    stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.18),
                            .init(color: .black, location: 0.82), .init(color: .clear, location: 1)],
                    startPoint: .leading, endPoint: .trailing
                )
            }
            .overlay(alignment: .bottom) {
                Image(systemName: "triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(accent)
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(width: proxy.size.width))
            .onHover { isHovering = $0 }
        }
        .onAppear {
            position = seconds
            step = Self.step(for: seconds)
            installScrollMonitor()
        }
        .onDisappear {
            removeScrollMonitor()
            holdTask?.cancel()
        }
        .onChange(of: selection) { oldValue, value in
            if value != seconds { seconds = value }
            glow(at: value)
            if hapticEnabled, oldValue != 0 {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            }
        }
        .onChange(of: seconds) { _, value in
            // Changed from elsewhere (e.g. the timer was reset): move the ruler to match.
            guard dragStart == nil, !isScrolling, value != selection else { return }
            step = Self.step(for: value)
            withAnimation(.snappy) { position = value }
        }
        .sensoryFeedback(.levelChange, trigger: isFine)
    }

    // MARK: Interaction

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { drag in
                if dragStart == nil {
                    dragStart = position
                    dragStartLocation = drag.startLocation
                    startHoldTimer()
                }
                // Moving before the hold completes means a normal drag: whole minutes again.
                if !isFine, abs(drag.translation.width) > 3 {
                    holdTask?.cancel()
                    step = 60
                }
                guard let start = dragStart, abs(drag.translation.width) > 0 || isFine else { return }
                position = Self.rubberBanded(start - TimeInterval(drag.translation.width / pointsPerSecond))
            }
            .onEnded { drag in
                holdTask?.cancel()
                let start = dragStart ?? position
                dragStart = nil
                if abs(drag.translation.width) < 3, !isFine {
                    // A click: select the tick under it.
                    let tapped = position + TimeInterval((drag.location.x - width / 2) / pointsPerSecond)
                    step = 60
                    settle(at: Self.snapped(tapped, step: step))
                    return
                }
                let predicted = start - TimeInterval(drag.predictedEndTranslation.width / pointsPerSecond)
                settle(at: Self.snapped(predicted, step: step))
                if isFine { zoomOutSoon() }
            }
    }

    private func startHoldTimer() {
        holdTask?.cancel()
        holdTask = Task {
            try? await Task.sleep(for: Self.fineHoldDuration)
            guard !Task.isCancelled else { return }
            step = 15
            withAnimation(.spring(duration: 0.45, bounce: 0.15)) { isFine = true }
        }
    }

    private func zoomOutSoon() {
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard dragStart == nil else { return }
            withAnimation(.spring(duration: 0.45, bounce: 0.1)) { isFine = false }
        }
    }

    private func settle(at value: TimeInterval) {
        withAnimation(.spring(duration: 0.5, bounce: 0.2)) { position = value }
    }

    /// Trackpad and mouse-wheel scrolling over the ruler. A local event monitor sees scroll events
    /// sent to this app; while the pointer is over the ruler they move it and are consumed.
    private func installScrollMonitor() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard isHovering else { return event }
            handleScroll(event)
            return nil
        }
    }

    private func removeScrollMonitor() {
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        scrollMonitor = nil
    }

    private func handleScroll(_ event: NSEvent) {
        guard event.hasPreciseScrollingDeltas else {
            // A mouse wheel: one minute per notch.
            let notch = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.scrollingDeltaX
            step = 60
            settle(at: Self.snapped(selection + (notch > 0 ? -60 : 60), step: step))
            return
        }
        // Trackpad: follow the fingers (and macOS's momentum after they lift), then snap when it stops.
        let delta = abs(event.scrollingDeltaX) >= abs(event.scrollingDeltaY) ? event.scrollingDeltaX : event.scrollingDeltaY
        if !isScrolling { step = 60 }
        isScrolling = true
        position = Self.rubberBanded(position - TimeInterval(delta / pointsPerSecond))

        let fingersLifted = event.phase == .ended || event.phase == .cancelled
        let momentumOver = event.momentumPhase == .ended || event.momentumPhase == .cancelled
        if (fingersLifted && event.momentumPhase == []) || momentumOver {
            isScrolling = false
            settle(at: selection)
        }
    }

    /// The tick that just became the selection lights up and its glow fades, like the iOS picker.
    private func glow(at value: TimeInterval) {
        glowTask?.cancel()
        glowingSeconds = value
        glowAmount = 1
        glowTask = Task {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.5)) { glowAmount = 0 }
        }
    }
}

/// Draws only the visible ticks, in one view. Conforming to Animatable lets SwiftUI interpolate
/// position, zoom and glow frame by frame (a Canvas on its own would jump to final values).
private struct RulerCanvas: View, Animatable {
    let accent: Color
    var position: Double
    var pointsPerSecond: Double
    var glow: Double
    let glowingSeconds: Double?
    let selection: Double

    var animatableData: AnimatablePair<AnimatablePair<Double, Double>, Double> {
        get { AnimatablePair(AnimatablePair(position, pointsPerSecond), glow) }
        set {
            position = newValue.first.first
            pointsPerSecond = newValue.first.second
            glow = newValue.second
        }
    }

    private static let labelY: CGFloat = 8
    private static let tickBottom: CGFloat = 58
    /// The glow's hot center: the accent pushed most of the way to white.
    private var glowCore: Color { Color(nsColor: NSColor(accent).blended(withFraction: 0.65, of: .white) ?? .white) }

    var body: some View {
        Canvas { context, size in
            let coarse = Double(DurationRuler.pointsPerSecond(fine: false))
            let fine = Double(DurationRuler.pointsPerSecond(fine: true))
            // 0 when zoomed out, 1 when zoomed in; drives the quarter ticks and extra labels fading in.
            let fineness = min(max((pointsPerSecond - coarse) / (fine - coarse), 0), 1)

            let centerX = Double(size.width) / 2
            let halfSpan = centerX / pointsPerSecond
            let lastSlot = Int(DurationRuler.visibleRange.upperBound / 15)
            let firstVisible = max(0, Int(((position - halfSpan) / 15).rounded(.down)))
            let lastVisible = min(lastSlot, Int(((position + halfSpan) / 15).rounded(.up)))
            guard firstVisible <= lastVisible else { return }

            for slot in firstVisible...lastVisible {
                let seconds = Double(slot) * 15
                let x = centerX + (seconds - position) * pointsPerSecond
                let isMinute = slot % 4 == 0
                let visibility = isMinute ? 1 : fineness
                guard visibility > 0.01 else { continue }

                let brightness = seconds <= selection ? 1.0 : 0.35
                let height: CGFloat = isMinute ? 34 : 22
                let tick = CGRect(x: x - 1.5, y: Self.tickBottom - height, width: 3, height: height)
                let tickPath = Path(roundedRect: tick, cornerRadius: 1.5)

                if seconds == glowingSeconds, glow > 0.01 {
                    // A glow is light spilling around the tick: a blurred halo behind it, then the tick lit up.
                    var halo = context
                    halo.addFilter(.blur(radius: 6))
                    halo.fill(Path(roundedRect: tick.insetBy(dx: -3, dy: -3), cornerRadius: 4),
                              with: .color(accent.opacity(0.9 * glow)))
                    context.fill(tickPath, with: .color(accent.opacity(brightness)))
                    context.fill(tickPath, with: .color(glowCore.opacity(glow)))
                } else {
                    context.fill(tickPath, with: .color(accent.opacity(brightness * visibility)))
                }

                if isMinute {
                    let minute = slot / 4
                    // Every five minutes normally; every minute fades in as the ruler zooms.
                    let labelVisibility = minute % 5 == 0 ? 1 : fineness
                    if labelVisibility > 0.01 {
                        let label = Text("\(minute)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(accent.opacity(brightness * labelVisibility))
                        context.draw(label, at: CGPoint(x: x, y: Self.labelY), anchor: .center)
                    }
                }
            }
        }
    }
}
