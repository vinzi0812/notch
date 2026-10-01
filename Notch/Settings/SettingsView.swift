import SwiftUI

/// The settings window's tabs. Each is a grouped form, the System Settings layout: labels on the
/// left, controls on the right, explanations under each section. The window shows them as toolbar
/// tabs (see `SettingsWindowController`).
enum SettingsTab: CaseIterable {
    case features, home, look, behavior, timer, calendar

    var title: String {
        switch self {
        case .features: "Features"
        case .home: "Home"
        case .look: "Look"
        case .behavior: "Behavior"
        case .timer: "Timer"
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
        case .calendar: "calendar"
        }
    }

    /// Each tab's size. The window resizes to it when the tab is selected, like System Settings.
    var size: CGSize {
        switch self {
        case .features: CGSize(width: 500, height: 456)
        case .home: CGSize(width: 500, height: 400)
        case .look: CGSize(width: 500, height: 440)
        case .behavior: CGSize(width: 500, height: 492)
        case .timer: CGSize(width: 500, height: 568)
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
            Section {
                ForEach(settings.featureOrder) { feature in
                    FeatureRow(feature: feature, isOn: Binding(
                        get: { settings.isVisible(feature) },
                        set: { settings.setVisible(feature, $0) }
                    ))
                }
                .onMove { settings.moveFeatures(fromOffsets: $0, toOffset: $1) }
            } footer: {
                Text("Drag to reorder the tabs above Home. Turning a feature off also removes its Home widgets.")
                    .foregroundStyle(.secondary)
            }
            ResetSection { settings.resetFeatures() }
        }
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

#Preview("Look") {
    SettingsTab.look.view(settings: .ephemeral())
}

#Preview("Behavior") {
    SettingsTab.behavior.view(settings: .ephemeral())
}
