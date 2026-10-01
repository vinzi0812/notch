//
//  BatteryStatus.swift
//  Notch
//
//  Created by Vineet Parmar on 26/09/26.
//


import IOKit.ps

struct BatteryStatus: Equatable {
    let level: Int
    let isCharging: Bool
    let isPluggedIn: Bool

    init(level: Int, isCharging: Bool, isPluggedIn: Bool) {
        self.level = level
        self.isCharging = isCharging
        self.isPluggedIn = isPluggedIn
    }

    init?(description: [String: Any]) {
        guard description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
              let current = description[kIOPSCurrentCapacityKey] as? Int,
              let max = description[kIOPSMaxCapacityKey] as? Int,
              max > 0 else { return nil }

        self.init(
            level: current * 100 / max,
            isCharging: description[kIOPSIsChargingKey] as? Bool ?? false,
            isPluggedIn: description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
        )
    }

    /// How full to draw the battery, 0...1. Drawn rather than an SF Symbol, which only comes in
    /// 0/25/50/75/100% (and only full when charging), so the icon shows the real level.
    var fillFraction: Double {
        min(max(Double(level) / 100, 0), 1)
    }

    /// The fill's color, like the menu bar's: green while charging, red when low on battery power.
    enum Tint: Equatable {
        case normal, charging, low
    }

    var tint: Tint {
        if isCharging { return .charging }
        if !isPluggedIn, level <= 20 { return .low }
        return .normal
    }

    /// What's drawn on top: a bolt while charging, a plug when connected but not charging (e.g. held
    /// at a limit by battery optimization), nothing on battery power.
    enum Badge: Equatable {
        case none, bolt, plug
    }

    var badge: Badge {
        if isCharging { return .bolt }
        if isPluggedIn { return .plug }
        return .none
    }

    func isPlugIn(after previous: BatteryStatus?) -> Bool {
        guard let previous else { return false }
        return !previous.isPluggedIn && isPluggedIn
    }
}
