import SwiftUI

/// The battery on Home: level and state, more of it as the widget grows.
struct BatteryWidget: View {
    let monitor: BatteryMonitor
    let size: WidgetSize

    var body: some View {
        if let status = monitor.status {
            Group {
                switch size {
                case .small:
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            BatteryIcon(status: status)
                            BatteryPercentage(status: status)
                                .font(.headline)
                        }
                        Text(status.stateText)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                case .wide:
                    HStack(spacing: 10) {
                        BatteryIcon(status: status, height: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            BatteryPercentage(status: status)
                                .font(.title3.bold())
                            Text(status.stateText)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        Spacer(minLength: 0)
                    }
                case .tall, .large:
                    BatterySection(status: status)
                }
            }
            .animation(.snappy, value: status)
        } else {
            Label("No battery", systemImage: "battery.0percent")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}
