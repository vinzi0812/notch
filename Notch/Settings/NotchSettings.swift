import Foundation
import SwiftUI   // for Array.move(fromOffsets:toOffset:), the same move a List reorder performs

/// The user's choices, saved in UserDefaults.
///
/// One observable object instead of scattered `@AppStorage` properties: the view model and the
/// app delegate need these values too, not just views, and injecting the UserDefaults makes every
/// setting testable without touching the real app's preferences.
@Observable
final class NotchSettings {
    /// Every feature, in the order the user arranged them.
    private(set) var featureOrder: [NotchFeature]
    private(set) var hiddenFeatures: Set<NotchFeature>

    /// Expanded width. Changing it resizes the panel, so it's reported through `onGeometryChanged`.
    var width: NotchWidth {
        didSet { save(width.rawValue, Keys.width); onGeometryChanged?() }
    }
    /// Corner radius of the expanded notch, in points.
    var cornerRadius: Double {
        didSet {
            let clamped = cornerRadius.clamped(to: Self.cornerRadiusRange)
            if cornerRadius != clamped { cornerRadius = clamped; return }
            save(cornerRadius, Keys.cornerRadius)
        }
    }
    var accent: NotchAccent {
        didSet { save(accent.rawValue, Keys.accent) }
    }
    var showsEars: Bool {
        didSet { save(showsEars, Keys.showsEars); onGeometryChanged?() }
    }
    /// The calendar page's layout. Month above needs a taller notch, so it reports a geometry change.
    var calendarLayout: CalendarLayout {
        didSet { save(calendarLayout.rawValue, Keys.calendarLayout); onGeometryChanged?() }
    }

    /// How long the pointer rests on the notch before it opens, in seconds (0 = instantly).
    var hoverDelay: Double {
        didSet {
            let clamped = hoverDelay.clamped(to: Self.hoverDelayRange)
            if hoverDelay != clamped { hoverDelay = clamped; return }
            save(hoverDelay, Keys.hoverDelay)
        }
    }
    var animationSpeed: AnimationSpeed {
        didSet { save(animationSpeed.rawValue, Keys.animationSpeed) }
    }
    /// Whether trackpad/mouse two-finger swipe navigates between tabs.
    var swipeNavigationEnabled: Bool {
        didSet { save(swipeNavigationEnabled, Keys.swipeNavigationEnabled) }
    }
    /// Whether hitting the notch with the mouse triggers tactile haptic feedback.
    var hapticFeedbackEnabled: Bool {
        didSet { save(hapticFeedbackEnabled, Keys.hapticFeedbackEnabled) }
    }
    /// Whether the settings gear button is shown in the tab bar.
    var showsSettingsButton: Bool {
        didSet { save(showsSettingsButton, Keys.showsSettingsButton) }
    }
    /// Features whose pop-up the user turned off. Stored as the exceptions, so a feature that gains
    /// a pop-up in a later version starts with it on.
    private(set) var mutedPopUps: Set<NotchFeature>

    /// The timer's length in seconds: set here or with the timer page's ruler, and kept across launches.
    var timerLength: Double {
        didSet {
            let clamped = timerLength.clamped(to: TimerState.durationRange)
            if timerLength != clamped { timerLength = clamped; return }
            save(timerLength, Keys.timerLength)
            if timerLength != oldValue { onTimerLengthChanged?(timerLength) }
        }
    }
    /// Lengths offered as one-tap chips on the timer page, in minutes.
    private(set) var timerPresets: [Double]
    var showsTimerPresets: Bool {
        didSet { save(showsTimerPresets, Keys.showsTimerPresets) }
    }
    var timerNotifies: Bool {
        didSet { save(timerNotifies, Keys.timerNotifies) }
    }
    var timerPlaysSound: Bool {
        didSet { save(timerPlaysSound, Keys.timerPlaysSound) }
    }
    /// Font size (pt) used in the terminal page.
    var terminalFontSize: Double {
        didSet { save(terminalFontSize, Keys.terminalFontSize) }
    }

    static let defaultTimerLength: Double = 25 * 60
    static let defaultTimerPresets: [Double] = [5, 10, 25, 45]
    static let presetRange: ClosedRange<Double> = 1...120
    static let terminalFontSizeRange: ClosedRange<Double> = 9...16

    @ObservationIgnored var onTimerLengthChanged: ((Double) -> Void)?

    static let hoverDelayRange: ClosedRange<Double> = 0...1
    static let defaultCornerRadius: Double = 24
    static let cornerRadiusRange: ClosedRange<Double> = 12...32

    /// Home's widgets and their sizes.
    var homeLayout: HomeLayout {
        didSet {
            if let data = try? JSONEncoder().encode(homeLayout) { save(data, Keys.homeLayout) }
        }
    }

    /// Called when a setting changes the notch's geometry (its width, or its ears).
    @ObservationIgnored var onGeometryChanged: (() -> Void)?

    /// Called after any change to which features are shown or their order.
    @ObservationIgnored var onFeaturesChanged: (() -> Void)?

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        featureOrder = Self.normalized(order: Self.features(forKey: Keys.featureOrder, in: defaults))
        hiddenFeatures = Set(Self.features(forKey: Keys.hiddenFeatures, in: defaults))
        // `didSet` doesn't run for assignments in init, so loading doesn't write anything back.
        width = defaults.string(forKey: Keys.width).flatMap(NotchWidth.init(rawValue:)) ?? .standard
        cornerRadius = (defaults.object(forKey: Keys.cornerRadius) as? Double)?.clamped(to: Self.cornerRadiusRange) ?? Self.defaultCornerRadius
        accent = defaults.string(forKey: Keys.accent).flatMap(NotchAccent.init(rawValue:)) ?? .orange
        showsEars = defaults.object(forKey: Keys.showsEars) as? Bool ?? true
        calendarLayout = defaults.string(forKey: Keys.calendarLayout).flatMap(CalendarLayout.init(rawValue:)) ?? .strip
        hoverDelay = (defaults.object(forKey: Keys.hoverDelay) as? Double)?.clamped(to: Self.hoverDelayRange) ?? 0
        animationSpeed = defaults.string(forKey: Keys.animationSpeed).flatMap(AnimationSpeed.init(rawValue:)) ?? .standard
        swipeNavigationEnabled = defaults.object(forKey: Keys.swipeNavigationEnabled) as? Bool ?? true
        hapticFeedbackEnabled = defaults.object(forKey: Keys.hapticFeedbackEnabled) as? Bool ?? false
        showsSettingsButton = defaults.object(forKey: Keys.showsSettingsButton) as? Bool ?? true
        mutedPopUps = Set(Self.features(forKey: Keys.mutedPopUps, in: defaults))
        homeLayout = defaults.data(forKey: Keys.homeLayout).flatMap { try? JSONDecoder().decode(HomeLayout.self, from: $0) } ?? .default
        timerLength = (defaults.object(forKey: Keys.timerLength) as? Double)?.clamped(to: TimerState.durationRange) ?? Self.defaultTimerLength
        timerPresets = Self.normalized(presets: defaults.array(forKey: Keys.timerPresets) as? [Double])
        showsTimerPresets = defaults.object(forKey: Keys.showsTimerPresets) as? Bool ?? true
        timerNotifies = defaults.object(forKey: Keys.timerNotifies) as? Bool ?? true
        timerPlaysSound = defaults.object(forKey: Keys.timerPlaysSound) as? Bool ?? true
        terminalFontSize = (defaults.object(forKey: Keys.terminalFontSize) as? Double)?.clamped(to: Self.terminalFontSizeRange) ?? 11
    }

    /// Settings kept in a throwaway domain, for tests and previews, so they never read or change the
    /// user's real preferences.
    static func ephemeral() -> NotchSettings {
        let name = "NotchSettings.ephemeral.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return NotchSettings(defaults: defaults)
    }

    // MARK: - Features

    /// The features to show, in order.
    var visibleFeatures: [NotchFeature] {
        featureOrder.filter { !hiddenFeatures.contains($0) }
    }

    func isVisible(_ feature: NotchFeature) -> Bool {
        !hiddenFeatures.contains(feature)
    }

    func setVisible(_ feature: NotchFeature, _ isVisible: Bool) {
        if isVisible {
            hiddenFeatures.remove(feature)
        } else {
            hiddenFeatures.insert(feature)
        }
        saveFeatures()
    }

    /// The shown features with a button on `side` of the camera, in tab bar order.
    func tabs(on side: NotchFeature.TabSide) -> [NotchFeature] {
        visibleFeatures.filter { $0.tabSide == side }
    }

    /// Moves `feature`'s tab to where `target`'s is, the way dropping one tab on another does.
    /// Tabs only move within their side of the camera.
    func moveTab(_ feature: NotchFeature, to target: NotchFeature) {
        guard feature != target, let side = feature.tabSide, target.tabSide == side,
              let from = featureOrder.firstIndex(of: feature),
              let to = featureOrder.firstIndex(of: target) else { return }
        featureOrder.move(fromOffsets: [from], toOffset: to > from ? to + 1 : to)
        saveFeatures()
    }

    func resetFeatures() {
        featureOrder = NotchFeature.allCases
        hiddenFeatures = []
        saveFeatures()
    }

    /// A saved order made trustworthy: duplicates dropped, and features the saved order doesn't know
    /// (added in a later version) appended at the end, so an update never loses a feature.
    static func normalized(order: [NotchFeature]) -> [NotchFeature] {
        var seen = Set<NotchFeature>()
        let known = order.filter { seen.insert($0).inserted }
        return known + NotchFeature.allCases.filter { !seen.contains($0) }
    }

    // MARK: - Look

    func resetLook() {
        width = .standard
        cornerRadius = Self.defaultCornerRadius
        accent = .orange
        showsEars = true
        showsSettingsButton = true
    }

    // MARK: - Behavior

    func showsPopUp(for feature: NotchFeature) -> Bool {
        !mutedPopUps.contains(feature)
    }

    func setShowsPopUp(for feature: NotchFeature, _ shows: Bool) {
        if shows {
            mutedPopUps.remove(feature)
        } else {
            mutedPopUps.insert(feature)
        }
        save(mutedPopUps.map(\.rawValue).sorted(), Keys.mutedPopUps)
    }

    func resetBehavior() {
        hoverDelay = 0
        animationSpeed = .standard
        swipeNavigationEnabled = true
        hapticFeedbackEnabled = false
        mutedPopUps = []
        save([String](), Keys.mutedPopUps)
    }

    // MARK: - Calendar

    func resetCalendar() {
        calendarLayout = .strip
    }

    // MARK: - Timer

    /// Sets one of the preset chips, in minutes (whole minutes, 1 to 120).
    func setTimerPreset(at index: Int, minutes: Double) {
        guard timerPresets.indices.contains(index) else { return }
        timerPresets[index] = minutes.rounded().clamped(to: Self.presetRange)
        save(timerPresets, Keys.timerPresets)
    }

    func resetTimer() {
        timerLength = Self.defaultTimerLength
        timerPresets = Self.defaultTimerPresets
        save(timerPresets, Keys.timerPresets)
        showsTimerPresets = true
        timerNotifies = true
        timerPlaysSound = true
    }

    /// Always four presets in range; anything else saved falls back to the defaults.
    static func normalized(presets: [Double]?) -> [Double] {
        guard let presets, presets.count == defaultTimerPresets.count else { return defaultTimerPresets }
        return presets.map { $0.rounded().clamped(to: presetRange) }
    }

    // MARK: - Storage

    private enum Keys {
        static let featureOrder = "settings.featureOrder"
        static let hiddenFeatures = "settings.hiddenFeatures"
        static let width = "settings.width"
        static let cornerRadius = "settings.cornerRadius"
        static let accent = "settings.accent"
        static let showsEars = "settings.showsEars"
        static let calendarLayout = "settings.calendarLayout"
        static let hoverDelay = "settings.hoverDelaySeconds"
        static let animationSpeed = "settings.animationSpeed"
        static let swipeNavigationEnabled = "settings.swipeNavigationEnabled"
        static let hapticFeedbackEnabled = "settings.hapticFeedbackEnabled"
        static let showsSettingsButton = "settings.showsSettingsButton"
        static let mutedPopUps = "settings.mutedPopUps"
        static let homeLayout = "settings.homeLayout"
        static let timerLength = "settings.timerLength"
        static let timerPresets = "settings.timerPresets"
        static let showsTimerPresets = "settings.showsTimerPresets"
        static let timerNotifies = "settings.timerNotifies"
        static let timerPlaysSound = "settings.timerPlaysSound"
        static let terminalFontSize = "settings.terminalFontSize"
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }

    private func saveFeatures() {
        defaults.set(featureOrder.map(\.rawValue), forKey: Keys.featureOrder)
        defaults.set(hiddenFeatures.map(\.rawValue).sorted(), forKey: Keys.hiddenFeatures)
        onFeaturesChanged?()
    }

    /// Unknown names (say, from a newer version's preferences) are skipped rather than failing.
    private static func features(forKey key: String, in defaults: UserDefaults) -> [NotchFeature] {
        (defaults.stringArray(forKey: key) ?? []).compactMap(NotchFeature.init(rawValue:))
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
