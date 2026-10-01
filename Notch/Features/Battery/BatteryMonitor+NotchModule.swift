//
//  BatteryMonitor+NotchModule.swift
//  Notch
//
//  Created by Vineet Parmar on 26/09/26.
//


import SwiftUI

extension BatteryMonitor: NotchModule {
    var feature: NotchFeature { .battery }

    var earPriority: Int? {
        status == nil ? nil : 0
    }

    @ViewBuilder
    func content(for placement: NotchPlacement) -> some View {
        if let status {
            Group {
                switch placement {
                case .leadingEar, .pill:
                    BatteryIcon(status: status)
                case .trailingEar:
                    BatteryPercentage(status: status)
                        .font(.caption2)
                case .headline, .page:
                    EmptyView()
                case .activityLeading:
                    ChargingBattery(status: status)
                case .activityTrailing:
                    BatteryPercentage(status: status)
                        .font(.title3.bold())
                case .activityDetail:
                    Text(status.isCharging ? "Charging" : "Connected")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            .animation(.snappy, value: status)
        }
    }
}

/// The battery as the menu bar draws it: an outline filled to the real level, green with a bolt
/// while charging, a plug when connected but not charging, red when low.
struct BatteryIcon: View {
    let status: BatteryStatus
    /// The body's height; everything else is in proportion.
    var height: CGFloat = 11

    private var fillColor: Color {
        switch status.tint {
        case .normal: .white.opacity(0.9)
        case .charging: .green
        case .low: .red
        }
    }

    var body: some View {
        HStack(spacing: height * 0.08) {
            ZStack {
                RoundedRectangle(cornerRadius: height * 0.3, style: .continuous)
                    .strokeBorder(.white.opacity(0.5), lineWidth: max(1, height * 0.1))
                GeometryReader { proxy in
                    // A sliver even when nearly empty, so a low battery never looks missing.
                    let width = status.fillFraction > 0 ? max(height * 0.18, proxy.size.width * status.fillFraction) : 0
                    RoundedRectangle(cornerRadius: height * 0.14, style: .continuous)
                        .fill(fillColor)
                        .frame(width: width)
                }
                .padding(height * 0.2)
                badge
            }
            .frame(width: height * 2.1, height: height)

            RoundedRectangle(cornerRadius: height * 0.1)
                .fill(.white.opacity(0.5))
                .frame(width: max(1.5, height * 0.14), height: height * 0.38)
        }
        .animation(.snappy, value: status)
        .accessibilityElement()
        .accessibilityLabel("Battery \(status.level)%\(status.isCharging ? ", charging" : status.isPluggedIn ? ", plugged in" : "")")
    }

    @ViewBuilder
    private var badge: some View {
        switch status.badge {
        case .none:
            EmptyView()
        case .bolt:
            Image(systemName: "bolt.fill")
                .font(.system(size: height * 0.78, weight: .heavy))
                .foregroundStyle(.white)
                // A dark edge so the bolt reads over the green fill, as in the menu bar.
                .shadow(color: .black.opacity(0.7), radius: 0, x: 0.6, y: 0.6)
                .shadow(color: .black.opacity(0.7), radius: 0, x: -0.6, y: -0.6)
                .transition(.scale.combined(with: .opacity))
        case .plug:
            // Cut dark into the fill when the fill is behind it, as the menu bar does; white otherwise.
            let overFill = status.fillFraction > 0.5
            Image(systemName: "powerplug.fill")
                .font(.system(size: height * 0.6, weight: .bold))
                .foregroundStyle(overFill ? .black : .white)
                .transition(.scale.combined(with: .opacity))
        }
    }
}

struct BatteryPercentage: View {
    let status: BatteryStatus

    var body: some View {
        Text("\(status.level)%")
            .monospacedDigit()
            .contentTransition(.numericText())
    }
}

struct BatterySection: View {
    let status: BatteryStatus

    var body: some View {
        VStack(spacing: 6) {
            BatteryIcon(status: status, height: 18)
            BatteryPercentage(status: status)
                .font(.title3.bold())
            Text(status.stateText)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}

extension BatteryStatus {
    var stateText: String {
        if isCharging {
            "Charging"
        } else if isPluggedIn {
            "Plugged in"
        } else {
            "On battery"
        }
    }
}

/// The battery drawn by hand so its fill can animate continuously (SF Symbols only have 0/25/50/75/100%).
/// Always green: it celebrates power arriving. At plug-in macOS usually reports "not charging yet",
/// so the accurate charging-vs-on-hold state is left to the ear icon (bolt vs plug) afterwards.
struct ChargingBattery: View {
    let status: BatteryStatus

    @State private var isFilled: Bool
    @State private var showsBolt: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(status: BatteryStatus, startsFinished: Bool = false) {
        self.status = status
        _isFilled = State(initialValue: startsFinished)
        _showsBolt = State(initialValue: startsFinished)
    }

    var body: some View {
        HStack(spacing: 1.5) {
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(.white.opacity(0.5), lineWidth: 1.5)
                .overlay(alignment: .leading) {
                    BatteryFill(level: isFilled ? Double(status.level) / 100 : 0)
                        .fill(.green)
                        .padding(3)
                }
                .overlay {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.white)
                        .scaleEffect(showsBolt ? 1 : 0.01)
                        .opacity(showsBolt ? 1 : 0)
                }
                .frame(width: 36, height: 17)

            RoundedRectangle(cornerRadius: 1)
                .fill(.white.opacity(0.5))
                .frame(width: 2.5, height: 6)
        }
        .onAppear {
            guard !reduceMotion else {
                isFilled = true
                showsBolt = true
                return
            }
            withAnimation(.easeOut(duration: 0.8).delay(0.25)) {
                isFilled = true
            }
            withAnimation(.bouncy(duration: 0.45, extraBounce: 0.25).delay(0.6)) {
                showsBolt = true
            }
        }
    }
}

/// The filled part of the battery; `level` (0...1) is animatable, so SwiftUI draws every in-between frame.
struct BatteryFill: Shape {
    var level: Double

    var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let clamped = min(max(level, 0), 1)
        let fillRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width * clamped, height: rect.height)
        return Path(roundedRect: fillRect, cornerRadius: 2.5)
    }
}
