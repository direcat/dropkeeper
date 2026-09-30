import SwiftUI

/// Dots on a line: duration stops, then Keep after an extra gap (design manual §7.3).
struct TimelineView: View {
    @Binding var model: TimelineModel
    let now: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let keepGap: CGFloat = TK.Space.m
    private let rowHeight: CGFloat = 20

    var body: some View {
        GeometryReader { geometry in
            let stopX = positions(width: geometry.size.width)
            ZStack(alignment: .topLeading) {
                selectedLabel
                    .position(x: clampedLabelX(stopX[model.selectedIndex], width: geometry.size.width), y: 8)
                lines(stopX)
                ForEach(model.stops.indices, id: \.self) { index in
                    dot(index).position(x: stopX[index], y: 28)
                    Text(label(for: model.stops[index]))
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(index == model.selectedIndex ? TK.Notch.textPrimary : TK.Notch.textSecondary)
                        .fixedSize()
                        .position(x: stopX[index], y: 48)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { value in
                    let nearest =
                        stopX.indices.min { abs(stopX[$0] - value.location.x) < abs(stopX[$1] - value.location.x) } ?? 0
                    select(nearest)
                })
        }
        .frame(height: 58)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Delete after"))
        .accessibilityValue(Text(accessibilityValue))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: select(model.selectedIndex + 1)
            case .decrement: select(model.selectedIndex - 1)
            @unknown default: break
            }
        }
    }

    private func positions(width: CGFloat) -> [CGFloat] {
        let inset: CGFloat = 20
        let count = model.stops.count
        guard count > 1 else { return [width / 2] }
        let step = (width - 2 * inset - keepGap) / CGFloat(count - 1)
        return (0..<count).map { index in
            inset + CGFloat(index) * step + (index == count - 1 ? keepGap : 0)
        }
    }

    private func clampedLabelX(_ centerX: CGFloat, width: CGFloat) -> CGFloat {
        min(max(centerX, 50), width - 50)
    }

    @ViewBuilder
    private func lines(_ stopX: [CGFloat]) -> some View {
        let lastDuration = max(0, model.stops.count - 2)
        Path { path in
            path.move(to: CGPoint(x: stopX[0], y: 28))
            path.addLine(to: CGPoint(x: stopX[lastDuration], y: 28))
        }
        .stroke(TK.Notch.hairline, lineWidth: 1)
        if case .duration = model.selected {
            Path { path in
                path.move(to: CGPoint(x: stopX[0], y: 28))
                path.addLine(to: CGPoint(x: stopX[model.selectedIndex], y: 28))
            }
            .stroke(TK.Notch.accent, lineWidth: 1)
        }
    }

    private func dot(_ index: Int) -> some View {
        let selected = index == model.selectedIndex
        let size = selected ? TK.Size.timelineDotSelected : TK.Size.timelineDot
        return Circle()
            .fill(model.isHighlighted(index) ? TK.Notch.accent : TK.Notch.hairline)
            .frame(width: size, height: size)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .onTapGesture { select(index) }
    }

    @ViewBuilder
    private var selectedLabel: some View {
        if let date = model.deletionDate(from: now) {
            Text(TimeLabels.deletion(at: date, now: now))
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(TK.Notch.accentText)
                .fixedSize()
        } else {
            Text("Kept")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(TK.Notch.textSecondary)
                .fixedSize()
        }
    }

    private func label(for stop: TimelineModel.Stop) -> String {
        switch stop {
        case .duration(let seconds): DurationLabel.short(seconds)
        case .keep: String(localized: "Keep")
        }
    }

    private var accessibilityValue: String {
        guard case .duration(let seconds) = model.selected, let date = model.deletionDate(from: now) else {
            return String(localized: "Keep it")
        }
        let time = TimeLabels.deletion(at: date, now: now)
        return String(localized: "Delete in \(DurationLabel.long(seconds)), at \(time)")
    }

    private func select(_ index: Int) {
        withAnimation(reduceMotion ? TK.Motion.reduced : TK.Motion.select) {
            model.select(index)
        }
    }
}

extension TimelineModel {
    /// Accent dots: the selected stop, plus every stop before it when a duration (a time) is selected.
    func isHighlighted(_ index: Int) -> Bool {
        if index == selectedIndex { return true }
        guard case .duration = selected else { return false }
        return index < selectedIndex
    }
}
