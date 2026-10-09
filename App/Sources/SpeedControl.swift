import SwiftUI
import WorkoutKit

/// A large mph value with −1, −0.1, +0.1, +1 buttons, matching the treadmill's knob and jump buttons.
struct SpeedControl: View {
    let speed: Speed
    var isLarge = false
    let onChange: (Speed) -> Void

    var body: some View {
        HStack(spacing: 8) {
            stepButton("−1", steps: -10)
            stepButton("−", steps: -1)
            Text(String(format: "%.1f", speed.mph))
                .font(.system(size: isLarge ? 44 : 34, weight: .bold, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .fixedSize()
                .frame(minWidth: isLarge ? 96 : 80)
                .accessibilityLabel("Speed \(RunFormatting.speed(speed))")
            stepButton("+", steps: 1)
            stepButton("+1", steps: 10)
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottom) {
            Text("mph").font(.caption).foregroundStyle(.secondary).offset(y: isLarge ? 20 : 16)
        }
        .padding(.bottom, 12)
    }

    private func stepButton(_ title: String, steps: Int) -> some View {
        Button(title) { onChange(speed.stepped(by: steps)) }
            .font(.system(size: isLarge ? 24 : 20, weight: .semibold, design: .rounded))
            .frame(minWidth: isLarge ? 52 : 44, minHeight: isLarge ? 60 : 44)
            .buttonStyle(.bordered)
            .accessibilityIdentifier("speed-step-\(steps)")
            .accessibilityLabel(
                steps > 0 ? "Increase speed \(Double(steps) / 10) mph" : "Decrease speed \(Double(-steps) / 10) mph")
    }
}
