import Foundation

/// A feature the user can show, hide and reorder in Settings.
///
/// The raw values are what gets saved, so renaming a case would lose the user's choices for it.
enum NotchFeature: String, CaseIterable, Codable, Identifiable {
    case battery
    case timer
    case calendar
    case files
    case nowPlaying
    case systemStats
    case levels
    case devices
    case notes
    case calculator
    case terminal
    case mirror

    var id: String { rawValue }

    enum TabSide {
        /// A labelled tab, left of the camera.
        case leading
        /// An icon button, right of the camera.
        case trailing
    }

    /// Which side of the camera the feature's tab bar button sits on, or nil if it has none there.
    /// Must match its module's `NotchTab.Style`; a test checks.
    var tabSide: TabSide? {
        switch self {
        case .files, .notes, .terminal: .leading
        case .mirror, .calculator: .trailing
        default: nil
        }
    }

    var title: String {
        switch self {
        case .battery: "Battery"
        case .timer: "Timer"
        case .calendar: "Calendar"
        case .files: "Files"
        case .nowPlaying: "Now Playing"
        case .mirror: "Mirror"
        case .systemStats: "System Stats"
        case .levels: "Volume & Brightness"
        case .devices: "Devices"
        case .notes: "Notes"
        case .calculator: "Calculator"
        case .terminal: "Terminal"
        }
    }

    var symbol: String {
        switch self {
        case .battery: "battery.75percent"
        case .timer: "timer"
        case .calendar: "calendar"
        case .files: "tray.full.fill"
        case .nowPlaying: "play.fill"
        case .mirror: "web.camera"
        case .systemStats: "gauge.with.dots.needle.33percent"
        case .levels: "speaker.wave.2.fill"
        case .devices: "airpods.pro"
        case .notes: "note.text"
        case .calculator: NotchIcon.calculator   // our own glyph: SF Symbols has no calculator
        case .terminal: "terminal"
        }
    }

    var summary: String {
        switch self {
        case .battery: "Level and charging in the ears, and the charging animation"
        case .timer: "A countdown with a ruler to pick its length"
        case .calendar: "Your next event, and a countdown before meetings"
        case .files: "A shelf for files dropped onto the notch"
        case .nowPlaying: "What's playing in any app, with controls"
        case .mirror: "A live camera view, from a button beside the camera"
        case .systemStats: "CPU, GPU, memory and temperature widgets for Home"
        case .levels: "Shows volume and brightness in the notch instead of macOS's indicator"
        case .devices: "AirPods and other Bluetooth devices: a pop-up when they connect, and batteries"
        case .notes: "Quick notes in their own tab, and a Home widget"
        case .calculator: "A calculator from a button beside the camera, and a Home widget"
        case .terminal: "An embedded zsh shell, always a keystroke away"
        }
    }
}
