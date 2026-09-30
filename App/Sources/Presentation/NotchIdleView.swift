import SwiftUI

/// Closed notch: mark on the left, count (or the last-seconds countdown) on the right (design manual §7.1).
struct NotchIdleView: View {
    let count: Int
    let urgentSeconds: Int?
    let notchWidth: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    private let markSize: CGFloat = 14
    private let pulseDotSize: CGFloat = 5
    private let pulseDimmedOpacity = 0.3

    /// VoiceOver value while the last-seconds countdown runs: "Deleting in 0:07".
    nonisolated static func accessibilityValue(urgentSeconds: Int?) -> String? {
        urgentSeconds.map { String(localized: "Deleting in \(TimeLabels.countdown($0))") }
    }

    var body: some View {
        HStack(spacing: 0) {
            Image("MarkWhite")
                .resizable()
                .scaledToFit()
                .frame(width: markSize, height: markSize)
                .frame(width: NotchGeometry.sideWidth)
            Spacer(minLength: notchWidth)
            trailing
                .frame(width: NotchGeometry.sideWidth)
        }
        // The pulse runs only while the countdown is shown and restarts each time it appears.
        .onChange(of: urgentSeconds != nil, initial: true) { _, counting in
            pulse = counting
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(count) files scheduled"))
        .accessibilityValue(Text(verbatim: Self.accessibilityValue(urgentSeconds: urgentSeconds) ?? ""))
    }

    @ViewBuilder
    private var trailing: some View {
        if let urgentSeconds {
            HStack(spacing: TK.Space.xs) {
                Circle()
                    .fill(TK.Notch.urgent)
                    .frame(width: pulseDotSize, height: pulseDotSize)
                    .opacity(pulse && !reduceMotion ? pulseDimmedOpacity : 1)
                    .animation(reduceMotion ? nil : TK.Motion.pulse.repeatForever(autoreverses: true), value: pulse)
                Text(TimeLabels.countdown(urgentSeconds))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(TK.Notch.urgent)
            }
        } else {
            Text(verbatim: "\(count)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(TK.Notch.textPrimary)
        }
    }
}
