import SwiftUI

/// How wide the expanded notch is.
enum NotchWidth: String, CaseIterable, Identifiable {
    case compact
    case standard
    case wide

    var id: String { rawValue }

    var points: CGFloat {
        switch self {
        case .compact: 480
        case .standard: NotchGeometry.defaultExpandedWidth
        case .wide: 620
        }
    }

    var title: String {
        switch self {
        case .compact: "Compact"
        case .standard: "Standard"
        case .wide: "Wide"
        }
    }
}

/// The color for the notch's highlights: the timer page and the playback progress.
/// Colors that carry meaning (green for charging, red for errors) don't follow it.
enum NotchAccent: String, CaseIterable, Identifiable {
    case orange, yellow, green, mint, blue, purple, pink

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .orange: Color(red: 0.96, green: 0.62, blue: 0.29)
        case .yellow: Color(red: 0.98, green: 0.82, blue: 0.29)
        case .green: Color(red: 0.42, green: 0.84, blue: 0.45)
        case .mint: Color(red: 0.38, green: 0.86, blue: 0.80)
        case .blue: Color(red: 0.36, green: 0.62, blue: 1.0)
        case .purple: Color(red: 0.70, green: 0.52, blue: 1.0)
        case .pink: Color(red: 1.0, green: 0.48, blue: 0.68)
        }
    }
}

/// How the calendar page lays out the month and the selected day's events.
enum CalendarLayout: String, CaseIterable, Identifiable {
    /// Every day of the month in a scrolling strip, the events below.
    case strip
    /// A month grid on the left, the events on the right.
    case beside
    /// A month grid on top, the events below; the notch grows taller for it.
    case above

    var id: String { rawValue }

    var title: String {
        switch self {
        case .strip: "Day strip"
        case .beside: "Month beside"
        case .above: "Month above"
        }
    }
}

extension EnvironmentValues {
    /// The user's accent, set once at the top of the notch so any feature's view can read it.
    @Entry var notchAccent: Color = NotchAccent.orange.color
    /// The timer page's preset chips, in seconds; empty when the user turned them off.
    @Entry var timerPresets: [TimeInterval] = []
    @Entry var calendarLayout: CalendarLayout = .strip
}
