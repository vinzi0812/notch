import Foundation

/// How fast the notch's own motion runs: opening, closing, resizing, pop-ups and ear handovers.
enum AnimationSpeed: String, CaseIterable, Identifiable {
    case relaxed
    case standard
    case quick

    var id: String { rawValue }

    /// Passed to `Animation.speed(_:)`: above 1 is faster. It scales the whole animation, delays
    /// included, so the choreography keeps its shape and bounce.
    var multiplier: Double {
        switch self {
        case .relaxed: 0.8
        case .standard: 1
        case .quick: 1.35
        }
    }

    var title: String {
        switch self {
        case .relaxed: "Relaxed"
        case .standard: "Standard"
        case .quick: "Quick"
        }
    }
}

extension NotchFeature {
    /// The pop-up this feature can show while the notch is collapsed, if it has one.
    var popUpTitle: String? {
        switch self {
        case .battery: "Charger connected"
        case .timer: "Timer finished"
        case .calendar: "Meeting starting"
        case .nowPlaying: "New track"
        case .devices: "Device connected"
        case .files, .mirror, .systemStats, .levels, .notes, .calculator, .terminal: nil
        }
    }

    static var withPopUps: [NotchFeature] { allCases.filter { $0.popUpTitle != nil } }
}
