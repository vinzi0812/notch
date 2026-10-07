import SwiftUI

/// The settings window's tabs. Each is a grouped form, the System Settings layout: labels on the
/// left, controls on the right, explanations under each section. The window shows them as toolbar
/// tabs (see `SettingsWindowController`).
enum SettingsTab: CaseIterable {
    case features, home, look, behavior, timer, calendar, terminal

    var title: String {
        switch self {
        case .features: "Features"
        case .home: "Home"
        case .look: "Look"
        case .behavior: "Behavior"
        case .timer: "Timer"
        case .terminal: "Terminal"
        case .calendar: "Calendar"
        }
    }

    var symbol: String {
        switch self {
        case .features: "square.grid.2x2"
        case .home: "rectangle.3.group"
        case .look: "paintbrush"
        case .behavior: "cursorarrow.motionlines"
        case .timer: "timer"
        case .terminal: "terminal"
        case .calendar: "calendar"
        }
    }

    /// Each tab's size. The window resizes to it when the tab is selected, like System Settings.
    var size: CGSize {
        switch self {
        case .features: CGSize(width: 500, height: 540)
        case .home: CGSize(width: 500, height: 400)
        case .look: CGSize(width: 500, height: 440)
        case .behavior: CGSize(width: 500, height: 492)
        case .timer: CGSize(width: 500, height: 568)
        case .terminal: CGSize(width: 500, height: 220)
        case .calendar: CGSize(width: 500, height: 460)
        }
    }

    @MainActor @ViewBuilder
    func view(settings: NotchSettings) -> some View {
        Group {
            switch self {
            case .features: FeaturesSettings(settings: settings)
            case .home: HomeSettings(settings: settings)
            case .look: LookSettings(settings: settings)
            case .behavior: BehaviorSettings(settings: settings)
            case .timer: TimerSettings(settings: settings)
            case .terminal: TerminalSettings(settings: settings)
            case .calendar: CalendarSettings(settings: settings)
            }
        }
        .formStyle(.grouped)
        .frame(width: size.width, height: size.height)
    }
}

/// A Reset button at the bottom right of a tab, in the same place on every tab.
private struct ResetSection: View {
    let action: () -> Void

    var body: some View {
        Section {} footer: {
            HStack {
                Spacer()
                Button("Reset", action: action)
                    .glassButtonStyle()
            }
        }
    }
}

/// Which features appear, and in what order.
struct FeaturesSettings: View {
    let settings: NotchSettings

    var body: some View {
        Form {
            Section("Tab Order") {
                TabOrderBar(settings: settings)
            }
            Section {
                ForEach(NotchFeature.allCases) { feature in
                    FeatureRow(feature: feature, isOn: Binding(
                        get: { settings.isVisible(feature) },
                        set: { settings.setVisible(feature, $0) }
                    ))
                }
            } footer: {
                Text("Turning a feature off also removes its tab and Home widgets.")
                    .foregroundStyle(.secondary)
            }
            ResetSection { settings.resetFeatures() }
        }
    }
}

/// A copy of the notch's tab bar to put the tabs in order: drag a tab sideways past its neighbors.
/// Home stays first, and tabs stay on their side of the camera, as in the notch.
private struct TabOrderBar: View {
    let settings: NotchSettings

    private struct Drag {
        let feature: NotchFeature
        /// How far the tab has moved from its place, following the pointer.
        var offset: CGFloat
        /// The slot it would land in, in its side's order.
        var target: Int
        /// Released and gliding into its slot; the order is saved when it gets there.
        var isSettling = false
    }

    /// Each tab's width. Positions are worked out from these alone, never read back from the
    /// screen, so the offsets a drag applies can't feed back into them.
    @State private var widths: [NotchFeature: CGFloat] = [:]
    @State private var drag: Drag?

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .top) {
                UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12)
                    .fill(.black)
                HStack(spacing: 0) {
                    HStack(spacing: 4) {
                        // Home is always first, so it's shown but can't be dragged.
                        Image(systemName: "house.fill")
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(.white.opacity(0.18), in: Capsule())
                            .help("Home is always first")
                        HStack(spacing: spacing(.leading)) {
                            ForEach(settings.tabs(on: .leading)) { tab($0, titled: settings.tabs(on: .leading).count <= 2) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // The camera housing.
                    UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8)
                        .fill(Color(white: 0.14))
                        .frame(width: 60)
                        .padding(.horizontal, 6)
                    HStack(spacing: spacing(.trailing)) {
                        ForEach(settings.tabs(on: .trailing)) { tab($0, titled: false) }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.horizontal, 12)
                .frame(height: 30)
            }
            .frame(height: 30)
            .font(.caption.weight(.medium))
            .foregroundStyle(.white)

            Text("Drag a tab to move it. Home stays first, and tabs keep to their side of the camera.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }

    private func tab(_ feature: NotchFeature, titled: Bool) -> some View {
        let lifted = drag?.feature == feature
        return HStack(spacing: TabBarLayout.iconTitleGap) {
            NotchIcon(name: feature.symbol)
            if titled { Text(feature.title) }
        }
        .padding(.horizontal, titled ? 7 : 5)
        .padding(.vertical, 4)
        .foregroundStyle(.white.opacity(lifted ? 1 : 0.7))
        // Lifted, it's solid and casts a shadow, so it covers the tab it's passing over.
        .background {
            if lifted {
                Capsule().fill(Color(white: 0.24)).shadow(color: .black.opacity(0.6), radius: 4, y: 1)
            }
        }
        .contentShape(Capsule())
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { widths[feature] = $0 }
        .offset(x: offset(of: feature))
        .zIndex(lifted ? 1 : 0)
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in dragChanged(feature, by: value.translation.width) }
                .onEnded { _ in dragEnded(feature) }
        )
        .help("\(feature.title): drag to reorder")
    }

    private func spacing(_ side: NotchFeature.TabSide) -> CGFloat { side == .leading ? 4 : 6 }

    /// The tabs on `feature`'s side and their widths, in bar order.
    private func row(of feature: NotchFeature) -> (tabs: [NotchFeature], widths: [CGFloat], spacing: CGFloat)? {
        guard let side = feature.tabSide else { return nil }
        let tabs = settings.tabs(on: side)
        let widths = tabs.map { self.widths[$0] ?? 0 }
        return (tabs, widths, spacing(side))
    }

    /// The lifted tab follows the pointer; the tabs it has passed slide over to make room.
    private func offset(of feature: NotchFeature) -> CGFloat {
        guard let drag else { return 0 }
        if feature == drag.feature { return drag.offset }
        guard drag.feature.tabSide == feature.tabSide, let row = row(of: feature),
              let from = row.tabs.firstIndex(of: drag.feature),
              let index = row.tabs.firstIndex(of: feature) else { return 0 }
        return TabReorder.shift(of: index, from: from, to: drag.target, by: row.widths[from] + row.spacing)
    }

    private func dragChanged(_ feature: NotchFeature, by translation: CGFloat) {
        guard drag.map({ $0.feature == feature && !$0.isSettling }) ?? true,
              let row = row(of: feature), let from = row.tabs.firstIndex(of: feature) else { return }
        let offset = TabReorder.clamped(translation, from: from, widths: row.widths, spacing: row.spacing)
        let target = TabReorder.target(from: from, offset: offset, widths: row.widths, spacing: row.spacing)
        if drag?.target != target {
            withAnimation(.snappy(duration: 0.22)) {
                drag = Drag(feature: feature, offset: offset, target: target)
            }
        } else {
            drag?.offset = offset
        }
    }

    /// Glides the tab into its slot, then saves the order with no animation: by then every tab is
    /// drawn exactly where the new order puts it, so nothing jumps.
    private func dragEnded(_ feature: NotchFeature) {
        guard var settling = drag, settling.feature == feature, !settling.isSettling,
              let row = row(of: feature), let from = row.tabs.firstIndex(of: feature) else { return }
        let target = settling.target
        settling.offset = TabReorder.slotOffset(from: from, to: target, widths: row.widths, spacing: row.spacing)
        settling.isSettling = true
        withAnimation(.snappy(duration: 0.2)) {
            drag = settling
        } completion: {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                if target != from { settings.moveTab(feature, to: row.tabs[target]) }
                drag = nil
            }
        }
    }
}

/// The arithmetic behind dragging a tab in `TabOrderBar`, from the tabs' widths alone. Positions
/// are measured from the start of the row; `from` is the dragged tab's index.
enum TabReorder {
    /// Each tab's center, laid out left to right.
    static func centers(widths: [CGFloat], spacing: CGFloat) -> [CGFloat] {
        var x: CGFloat = 0
        return widths.map { width in
            defer { x += width + spacing }
            return x + width / 2
        }
    }

    /// Keeps the dragged tab within its row, so it never slides past the ends.
    static func clamped(_ offset: CGFloat, from: Int, widths: [CGFloat], spacing: CGFloat) -> CGFloat {
        let center = centers(widths: widths, spacing: spacing)[from]
        let total = widths.reduce(0, +) + spacing * CGFloat(max(0, widths.count - 1))
        let half = widths[from] / 2
        return min(max(offset, half - center), total - half - center)
    }

    /// The slot the dragged tab would land in. A neighbor makes way as soon as the dragged tab's
    /// leading edge (in the direction it's moving) reaches the neighbor's center.
    static func target(from: Int, offset: CGFloat, widths: [CGFloat], spacing: CGFloat) -> Int {
        let centers = centers(widths: widths, spacing: spacing)
        let edge = centers[from] + offset + (offset > 0 ? widths[from] / 2 : offset < 0 ? -widths[from] / 2 : 0)
        let passedRight = centers.indices.filter { $0 > from && edge > centers[$0] }.count
        let passedLeft = centers.indices.filter { $0 < from && edge < centers[$0] }.count
        return from + passedRight - passedLeft
    }

    /// How far the tab at `index` slides while the tab at `from` is dragged to slot `to`: tabs it
    /// has passed move one place back toward where it started.
    static func shift(of index: Int, from: Int, to: Int, by width: CGFloat) -> CGFloat {
        if from < index, index <= to { return -width }
        if to <= index, index < from { return width }
        return 0
    }

    /// The offset that puts the dragged tab exactly in slot `to`, where the saved order will draw it.
    static func slotOffset(from: Int, to: Int, widths: [CGFloat], spacing: CGFloat) -> CGFloat {
        var reordered = widths
        reordered.move(fromOffsets: [from], toOffset: to > from ? to + 1 : to)
        return centers(widths: reordered, spacing: spacing)[to] - centers(widths: widths, spacing: spacing)[from]
    }
}

/// Home's widgets: the same editor as Edit Home in the notch, with labelled tiles.
struct HomeSettings: View {
    let settings: NotchSettings

    private var columns: Int { HomeLayout.columns(forWidth: settings.width.points) }

    var body: some View {
        Form {
            Section {
                HomeLayoutEditor(settings: settings, columns: columns, spacing: 6, cornerRadius: 10) { widget in
                    WidgetDiagramTile(widget: widget)
                }
                .frame(height: 150)
                .padding(.vertical, 8)
                .environment(\.colorScheme, .dark)
                .environment(\.notchAccent, settings.accent.color)
                .padding(10)
                .background(.black, in: .rect(cornerRadius: 14, style: .continuous))
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Drag a widget to move it, drag its corner to resize, − to remove. \(settings.width.title) width has \(columns) columns; on Home, widgets grow to fill any gaps.")
                    OverflowNote(settings: settings, columns: columns)
                        .foregroundStyle(.orange)
                }
                .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    AddWidgetMenu(settings: settings)
                        .menuStyle(.button)
                        .glassButtonStyle()
                        .fixedSize()
                    Spacer()
                    Button("Reset") { settings.homeLayout = .default }
                        .glassButtonStyle()
                }
            } footer: {
                Text("You can also arrange Home right in the notch: right-click it and choose Edit Home.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A widget in the Settings editor: its icon, name and size, on an accent tint.
private struct WidgetDiagramTile: View {
    let widget: HomeWidget
    @Environment(\.notchAccent) private var accent

    var body: some View {
        VStack(spacing: 3) {
            NotchIcon(name: widget.kind.symbol, size: widget.size == .small ? 14 : 18)
                .font(.system(size: widget.size == .small ? 13 : 17, weight: .semibold))
            if widget.size != .small {
                Text(widget.kind.title)
                    .font(.caption.weight(.semibold))
            }
            Text(widget.size == .small ? widget.kind.shortTitle : widget.size.title)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
        }
        .foregroundStyle(.white)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(accent.opacity(0.18))
    }
}

/// Size, corners, accent color and ears, with a live preview of the expanded notch.
struct LookSettings: View {
    @Bindable var settings: NotchSettings

    var body: some View {
        Form {
            Section {
                NotchLookPreview(settings: settings)
            }

            Section {
                Picker("Width", selection: $settings.width) {
                    ForEach(NotchWidth.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                LabeledContent("Corners") {
                    SteppedSlider(value: $settings.cornerRadius, in: NotchSettings.cornerRadiusRange, step: 1) {
                        "\(Int($0)) pt"
                    }
                }

                LabeledContent("Accent") {
                    HStack(spacing: 8) {
                        ForEach(NotchAccent.allCases) { accent in
                            AccentSwatch(accent: accent, isSelected: settings.accent == accent) {
                                settings.accent = accent
                            }
                        }
                    }
                }
            }

            Section {
                Toggle("Show ears when collapsed", isOn: $settings.showsEars)
                Toggle("Show settings button in tab bar", isOn: $settings.showsSettingsButton)
            } footer: {
                Text("The ears beside the camera show the battery, a running timer or what's playing. Pop-ups still appear when they're off.")
                    .foregroundStyle(.secondary)
            }

            ResetSection { settings.resetLook() }
        }
    }
}

/// Hover delay, which pop-ups appear, and how fast the notch moves.
struct BehaviorSettings: View {
    @Bindable var settings: NotchSettings

    var body: some View {
        Form {
            Section {
                LabeledContent("Open on hover") {
                    SteppedSlider(value: $settings.hoverDelay, in: NotchSettings.hoverDelayRange, step: 0.05) {
                        $0 == 0 ? "Instantly" : String(format: "%.2g s", $0)
                    }
                }
            } footer: {
                Text("A short delay keeps the notch from opening when the pointer just passes by. Dragging a file always opens it right away.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Animation speed", selection: $settings.animationSpeed) {
                    ForEach(AnimationSpeed.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("With Reduce Motion on in System Settings, the notch fades instead of springing.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Swipe to switch tabs", isOn: $settings.swipeNavigationEnabled)
                Toggle("Haptic feedback", isOn: $settings.hapticFeedbackEnabled)
            } footer: {
                Text("Swipe left or right with two fingers on the trackpad or mouse to switch tabs. Haptic feedback plays a subtle trackpad click when hitting the notch and scrolling the timer ruler.")
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(NotchFeature.withPopUps) { feature in
                    Toggle(feature.popUpTitle ?? feature.title, isOn: Binding(
                        get: { settings.showsPopUp(for: feature) },
                        set: { settings.setShowsPopUp(for: feature, $0) }
                    ))
                    .disabled(!settings.isVisible(feature))
                }
            } header: {
                Text("Pop-ups")
            } footer: {
                Text("Shown briefly while the notch is closed. Hidden features can't show theirs.")
                    .foregroundStyle(.secondary)
            }

            ResetSection { settings.resetBehavior() }
        }
    }
}

/// The timer's length, preset chips, and its notification.
struct TimerSettings: View {
    @Bindable var settings: NotchSettings

    var body: some View {
        Form {
            Section {
                LabeledContent("Length") {
                    Stepper(value: $settings.timerLength, in: TimerState.durationRange, step: 60) {
                        Text(TimerFormat.string(seconds: Int(settings.timerLength)))
                            .monospacedDigit()
                            .frame(minWidth: 64, alignment: .trailing)
                    }
                }
            } footer: {
                Text("The ruler on the timer page sets this too. The last length you pick is kept when the app restarts.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Show presets on the timer page", isOn: $settings.showsTimerPresets)
                ForEach(settings.timerPresets.indices, id: \.self) { index in
                    LabeledContent("Preset \(index + 1)") {
                        Stepper(value: Binding(
                            get: { settings.timerPresets[index] },
                            set: { settings.setTimerPreset(at: index, minutes: $0) }
                        ), in: NotchSettings.presetRange, step: 1) {
                            Text("\(Int(settings.timerPresets[index])) min")
                                .monospacedDigit()
                                .frame(minWidth: 64, alignment: .trailing)
                        }
                    }
                    .disabled(!settings.showsTimerPresets)
                }
            } header: {
                Text("Presets")
            }

            Section {
                Toggle("Notify when a timer finishes", isOn: $settings.timerNotifies)
                Toggle("Play a sound", isOn: $settings.timerPlaysSound)
                    .disabled(!settings.timerNotifies)
            } footer: {
                Text("The notification also appears in Notification Center. The notch's own pop-up is under Behavior.")
                    .foregroundStyle(.secondary)
            }

            ResetSection { settings.resetTimer() }
        }
    }
}

/// The calendar page's layout, with a live preview of it.
struct CalendarSettings: View {
    @Bindable var settings: NotchSettings

    var body: some View {
        Form {
            Section {
                CalendarLayoutPreview(settings: settings)
            }

            Section {
                Picker("Layout", selection: $settings.calendarLayout) {
                    ForEach(CalendarLayout.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(Self.explanation(settings.calendarLayout))
                    .foregroundStyle(.secondary)
            }

            ResetSection { settings.resetCalendar() }
        }
    }

    static func explanation(_ layout: CalendarLayout) -> String {
        switch layout {
        case .strip: "Every day of the month in a row you scroll, with the selected day's events below."
        case .beside: "A month grid next to the selected day's events, in the usual tall notch."
        case .above: "A month grid over the selected day's events. The notch grows taller on the calendar page to fit both."
        }
    }
}

/// The real calendar page, scaled down, with a few sample events around today: it springs between
/// layouts (and grows for Month above) as the setting changes, and follows the chosen width and accent.
private struct CalendarLayoutPreview: View {
    let settings: NotchSettings

    @State private var month = CalendarMonth(containing: .now)
    @State private var selected = Calendar.current.startOfDay(for: .now)
    private let events = CalendarLayoutPreview.sampleEvents()

    var body: some View {
        let width = settings.width.points
        let height = NotchGeometry.expandedHeight + NotchGeometry.headlineHeight
            + (settings.calendarLayout == .above ? NotchGeometry.calendarMonthAboveExtra : 0)
        let scale = min(0.72, 420 / width)
        let radius = settings.cornerRadius

        ZStack(alignment: .top) {
            UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius)
                .fill(.black)
            VStack(spacing: 0) {
                Color.clear.frame(height: 32)   // the tab bar's band
                CalendarPageContent(month: $month, selected: $selected, events: events)
                    .padding(.horizontal, 24)
                    .padding(.top, 2)
                    .padding(.bottom, 10)
                    .frame(maxHeight: .infinity)
            }
            // The camera housing, for scale.
            UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8)
                .fill(Color(white: 0.12))
                .frame(width: 180, height: 32)
        }
        .frame(width: width, height: height)
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius))
        .foregroundStyle(.white)
        .environment(\.calendarLayout, settings.calendarLayout)
        .environment(\.notchAccent, settings.accent.color)
        .environment(\.colorScheme, .dark)
        .allowsHitTesting(false)
        .scaleEffect(scale, anchor: .top)
        .frame(width: width * scale, height: height * scale, alignment: .top)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .animation(.spring(duration: 0.5, bounce: 0.3), value: settings.calendarLayout)
        .animation(.spring(duration: 0.5, bounce: 0.3), value: settings.width)
    }

    /// A believable day: a call, a review, something tomorrow, a birthday later in the week.
    static func sampleEvents(now: Date = .now) -> [CalendarEvent] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        func at(_ dayOffset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(byAdding: DateComponents(day: dayOffset, hour: hour, minute: minute), to: today)!
        }
        let blue = CalendarEvent.EventColor(red: 0.2, green: 0.55, blue: 1)
        let purple = CalendarEvent.EventColor(red: 0.7, green: 0.45, blue: 1)
        let green = CalendarEvent.EventColor(red: 0.3, green: 0.8, blue: 0.4)
        return [
            CalendarEvent(id: "standup", title: "Team standup", start: at(0, 10), end: at(0, 10, 15), isAllDay: false,
                          color: blue, callURL: URL(string: "https://meet.google.com/abc-defg-hij")),
            CalendarEvent(id: "review", title: "Design review", start: at(0, 14, 30), end: at(0, 15, 30), isAllDay: false,
                          color: purple, location: "Room 4B"),
            CalendarEvent(id: "gym", title: "Gym", start: at(0, 18), end: at(0, 19), isAllDay: false, color: green),
            CalendarEvent(id: "lunch", title: "Lunch with Sam", start: at(1, 13), end: at(1, 14), isAllDay: false, color: green),
            CalendarEvent(id: "birthday", title: "Birthday", start: at(3, 0), end: at(4, 0), isAllDay: true, color: purple),
            CalendarEvent(id: "planning", title: "Sprint planning", start: at(-4, 10), end: at(-4, 11), isAllDay: false, color: blue),
        ]
    }
}

/// A slider that snaps to `step` without drawing a tick mark for every step (which `Slider`'s own
/// `step:` does), with its value shown beside it.
private struct SteppedSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let label: (Double) -> String

    init(value: Binding<Double>, in range: ClosedRange<Double>, step: Double, label: @escaping (Double) -> String) {
        _value = value
        self.range = range
        self.step = step
        self.label = label
    }

    var body: some View {
        HStack(spacing: 10) {
            Slider(value: Binding(
                get: { value },
                set: { value = (($0 / step).rounded() * step).clamped(to: range) }
            ), in: range)
            Text(label(value))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .trailing)
        }
        .frame(width: 230)
    }
}

/// A scaled-down expanded notch that follows the settings as they change.
private struct NotchLookPreview: View {
    let settings: NotchSettings
    private let scale: CGFloat = 0.62

    var body: some View {
        let size = CGSize(width: settings.width.points * scale, height: NotchGeometry.expandedHeight * scale)
        let radius = settings.cornerRadius * scale
        let tabBarH: CGFloat = 32 * scale
        ZStack(alignment: .top) {
            UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius)
                .fill(.black)
                .frame(width: size.width, height: size.height)
                .overlay(alignment: .bottom) {
                    // A stand-in for accented content, like playback progress.
                    Capsule()
                        .fill(.white.opacity(0.25))
                        .overlay(alignment: .leading) {
                            Capsule().fill(settings.accent.color).frame(width: size.width * 0.35)
                        }
                        .frame(width: size.width * 0.6, height: 3)
                        .padding(.bottom, 22)
                }
                .overlay(alignment: .topTrailing) {
                    if settings.showsSettingsButton {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 8 * scale, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                            .padding(.trailing, 14 * scale)
                            .frame(height: tabBarH)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.snappy, value: settings.showsSettingsButton)
            // The camera housing, for scale.
            UnevenRoundedRectangle(bottomLeadingRadius: 6, bottomTrailingRadius: 6)
                .fill(Color(white: 0.12))
                .frame(width: 180 * scale, height: 32 * scale)
        }
        .frame(maxWidth: .infinity)
        .frame(height: NotchGeometry.expandedHeight * scale)
        .padding(.vertical, 8)
        .animation(.spring(duration: 0.5, bounce: 0.3), value: settings.width)
        .animation(.spring(duration: 0.5, bounce: 0.3), value: settings.cornerRadius)
    }
}

private struct AccentSwatch: View {
    let accent: NotchAccent
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            // A drop of tinted glass, like the accent picker in System Settings.
            Circle()
                .fill(.clear)
                .frame(width: 20, height: 20)
                .glassTinted(accent.color, in: Circle(), interactive: true)
                .overlay {
                    if isSelected {
                        Circle().fill(.white).frame(width: 7, height: 7)
                    }
                }
        }
        .buttonStyle(.plain)
        .help(accent.title)
        .accessibilityLabel(accent.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct FeatureRow: View {
    let feature: NotchFeature
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            NotchIcon(name: feature.symbol, size: 16)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(.tint, in: .rect(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title)
                Text(feature.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle(feature.title, isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.vertical, 4)
        .opacity(isOn ? 1 : 0.55)
    }
}

struct TerminalSettings: View {
    @Bindable var settings: NotchSettings

    var body: some View {
        Form {
            Section {
                LabeledContent("Font Size") {
                    SteppedSlider(value: $settings.terminalFontSize, in: NotchSettings.terminalFontSizeRange, step: 1) {
                        "\(Int($0)) pt"
                    }
                }
            } footer: {
                Text("The font size used for the terminal tab.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview("Look") {
    SettingsTab.look.view(settings: .ephemeral())
}

#Preview("Behavior") {
    SettingsTab.behavior.view(settings: .ephemeral())
}
