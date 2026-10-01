import SwiftUI

extension CalculatorModel: NotchModule {
    var feature: NotchFeature { .calculator }
    var earPriority: Int? { nil }

    /// An icon beside the mirror, on the right of the camera.
    var tab: NotchTab? { NotchTab(title: "Calculator", symbol: NotchIcon.calculator, style: .button) }

    var wantsTallPage: Bool { true }

    @ViewBuilder
    func content(for placement: NotchPlacement) -> some View {
        if placement == .page {
            CalculatorPage(model: self)
        }
    }
}

/// The expression and its live result on the left with recent calculations above; the keypad on the
/// right. Type on the keyboard (Return for =, Esc to clear) or tap the keys.
struct CalculatorPage: View {
    @Bindable var model: CalculatorModel
    @FocusState private var focused: Bool
    @State private var copied = false
    @Environment(\.textEditing) private var textEditing
    @Environment(\.notchAccent) private var accent

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .trailing, spacing: 2) {
                history
                Spacer(minLength: 0)
                TextField("0", text: $model.expression)
                    .textFieldStyle(.plain)
                    .font(.system(size: 24, weight: .light))
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .focused($focused)
                    .onSubmit { model.commit() }
                    .onKeyPress(.escape) {
                        // First Esc clears; with nothing typed, it lets go so the notch can close.
                        if model.expression.isEmpty { focused = false } else { model.expression = "" }
                        return .handled
                    }
                resultLine
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { focused = true }

            CalculatorKeypad { model.press($0) }
                .frame(width: 214)
        }
        .onChange(of: focused) { textEditing(focused) }
        .onDisappear { textEditing(false) }
    }

    private var history: some View {
        VStack(alignment: .trailing, spacing: 1) {
            ForEach(model.history.prefix(3).reversed()) { entry in
                Button {
                    model.use(entry)
                } label: {
                    Text("\(entry.expression) = \(Calculation.format(entry.result))")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .help("Use this result")
            }
        }
    }

    @ViewBuilder
    private var resultLine: some View {
        if let result = model.result {
            Button {
                model.copy(result)
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.2))
                    copied = false
                }
            } label: {
                Text(copied ? "Copied" : "= \(Calculation.format(result))")
                    .font(.system(size: 17, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
            }
            .buttonStyle(.plain)
            .help("Copy the result")
            .animation(.snappy, value: copied)
        } else {
            Text(" ")
                .font(.system(size: 17, weight: .semibold))
        }
    }
}

/// C ( ) ÷ / 7 8 9 × / 4 5 6 − / 1 2 3 + / 0 . ⌫ =
struct CalculatorKeypad: View {
    let press: (CalculatorModel.Key) -> Void
    @Environment(\.notchAccent) private var accent

    private let rows: [[(String, CalculatorModel.Key)]] = [
        [("C", .clear), ("(", .open), (")", .close), ("÷", .op("÷"))],
        [("7", .digit(7)), ("8", .digit(8)), ("9", .digit(9)), ("×", .op("×"))],
        [("4", .digit(4)), ("5", .digit(5)), ("6", .digit(6)), ("−", .op("−"))],
        [("1", .digit(1)), ("2", .digit(2)), ("3", .digit(3)), ("+", .op("+"))],
        [("0", .digit(0)), (".", .point), ("⌫", .backspace), ("=", .equals)],
    ]

    var body: some View {
        VStack(spacing: 5) {
            ForEach(rows.indices, id: \.self) { row in
                HStack(spacing: 5) {
                    ForEach(rows[row], id: \.0) { label, key in
                        keyButton(label, key)
                    }
                }
            }
        }
    }

    private func keyButton(_ label: String, _ key: CalculatorModel.Key) -> some View {
        let isOperator = ["÷", "×", "−", "+"].contains(label)
        let isEquals = key == .equals
        return Button {
            press(key)
        } label: {
            Text(label)
                .font(.system(size: 15, weight: isOperator || isEquals ? .semibold : .regular))
                .foregroundStyle(isEquals ? .black : isOperator ? accent : .white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    // = is the one solid key: tinted glass loses its color over the black notch.
                    if isEquals { Capsule().fill(accent) }
                }
                .glassControl(in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// The last result on Home; tapping opens the calculator.
struct CalculatorWidget: View {
    let model: CalculatorModel
    let size: WidgetSize
    @Environment(\.openNotchPage) private var openPage

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label {
                Text("Calculator")
            } icon: {
                NotchIcon(name: NotchIcon.calculator, size: 11)
            }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
            if let last = model.history.first {
                Text(Calculation.format(last.result))
                    .font(.system(size: size.rows == 2 ? 28 : 20, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if size != .small {
                    Text(last.expression)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
            } else {
                Text("Tap to calculate")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { openPage(model) }
    }
}
