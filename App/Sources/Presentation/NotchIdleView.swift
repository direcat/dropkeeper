import SwiftUI

/// Closed notch: mark on the left, count (or the last-seconds countdown) on the right (design manual §7.1).
struct NotchIdleView: View {
    let count: Int
    let urgentSeconds: Int?
    let notchWidth: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 0) {
            Image("MarkWhite")
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 14)
                .frame(width: NotchGeometry.sideWidth)
            Spacer(minLength: notchWidth)
            trailing
                .frame(width: NotchGeometry.sideWidth)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(count) files scheduled"))
    }

    @ViewBuilder
    private var trailing: some View {
        if let urgentSeconds {
            HStack(spacing: 4) {
                Circle()
                    .fill(TK.Notch.urgent)
                    .frame(width: 5, height: 5)
                    .opacity(pulse ? 0.3 : 1)
                    .animation(reduceMotion ? nil : TK.Motion.pulse.repeatForever(autoreverses: true), value: pulse)
                    .onAppear { pulse = true }
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
