import SwiftUI

/// Dots on a line: duration stops, then Keep after an extra gap (design manual §7.3).
struct TimelineView: View {
    @Binding var model: TimelineModel
    let now: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let keepGap: CGFloat = TK.Space.m
    /// Horizontal inset of the first and last dot inside the track.
    private let trackInset: CGFloat = 26
    /// Vertical centers of the three rows: deletion time, dots, stop labels.
    /// The dot row leaves room for the selected dot's halo (28 pt across) below the label row.
    private let labelRowY: CGFloat = 10
    private let dotRowY: CGFloat = 38
    private let stopLabelRowY: CGFloat = 66
    private let labelRowHeight: CGFloat = 20
    private let dotHitSize: CGFloat = 36
    private let totalHeight: CGFloat = 78

    var body: some View {
        GeometryReader { geometry in
            let stopX = positions(width: geometry.size.width)
            ZStack(alignment: .topLeading) {
                ClampedCenterLayout(centerX: stopX[model.selectedIndex]) { selectedLabel }
                    .frame(width: geometry.size.width, height: labelRowHeight)
                    .position(x: geometry.size.width / 2, y: labelRowY)
                lines(stopX)
                ForEach(model.stops.indices, id: \.self) { index in
                    dot(index).position(x: stopX[index], y: dotRowY)
                    Text(label(for: model.stops[index]))
                        .font(.system(size: TK.TextSize.small, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(index == model.selectedIndex ? TK.Notch.textPrimary : TK.Notch.textSecondary)
                        .fixedSize()
                        .position(x: stopX[index], y: stopLabelRowY)
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
        .frame(height: totalHeight)
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
        let count = model.stops.count
        guard count > 1 else { return [width / 2] }
        let step = (width - 2 * trackInset - keepGap) / CGFloat(count - 1)
        return (0..<count).map { index in
            trackInset + CGFloat(index) * step + (index == count - 1 ? keepGap : 0)
        }
    }

    @ViewBuilder
    private func lines(_ stopX: [CGFloat]) -> some View {
        let lastDuration = max(0, model.stops.count - 2)
        Path { path in
            path.move(to: CGPoint(x: stopX[0], y: dotRowY))
            path.addLine(to: CGPoint(x: stopX[lastDuration], y: dotRowY))
        }
        .stroke(TK.Notch.hairline, lineWidth: TK.Size.timelineTrackWidth)
        if case .duration = model.selected {
            Path { path in
                path.move(to: CGPoint(x: stopX[0], y: dotRowY))
                path.addLine(to: CGPoint(x: stopX[model.selectedIndex], y: dotRowY))
            }
            .stroke(TK.Notch.accent, lineWidth: TK.Size.timelineTrackWidth)
        }
    }

    private func dot(_ index: Int) -> some View {
        let selected = index == model.selectedIndex
        let size = selected ? TK.Size.timelineDotSelected : TK.Size.timelineDot
        return Circle()
            .fill(model.isHighlighted(index) ? TK.Notch.accent : TK.Notch.hairline)
            .frame(width: size, height: size)
            // Halo around the selected dot, so it stands out from the highlighted ones before it.
            .overlay {
                Circle()
                    .strokeBorder(TK.Notch.accent, lineWidth: TK.Size.timelineHaloWidth)
                    .padding(-(TK.Size.timelineHaloGap + TK.Size.timelineHaloWidth))
                    .opacity(selected ? 0.4 : 0)
            }
            .frame(width: dotHitSize, height: dotHitSize)
            .contentShape(Rectangle())
            .onTapGesture { select(index) }
    }

    @ViewBuilder
    private var selectedLabel: some View {
        if let date = model.deletionDate(from: now) {
            Text(TimeLabels.deletion(at: date, now: now))
                .font(.system(size: TK.TextSize.title, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(TK.Notch.accentText)
                .fixedSize()
        } else {
            Text("Kept")
                .font(.system(size: TK.TextSize.title, weight: .semibold))
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
            return String(localized: "Keep")
        }
        let time = TimeLabels.deletion(at: date, now: now)
        return String(localized: "Delete in \(DurationLabel.long(seconds)), at \(time)")
    }

    private func select(_ index: Int) {
        withAnimation(Self.selectionAnimation(reduceMotion: reduceMotion)) {
            model.select(index)
        }
    }

    /// Animation for moving the selected stop (tap, drag, arrows, VoiceOver); a plain fade under Reduce Motion.
    static func selectionAnimation(reduceMotion: Bool) -> Animation {
        reduceMotion ? TK.Motion.reduced : TK.Motion.select
    }
}

/// Places its single subview centered on `centerX`, shifted inward only as far as needed to stay inside the bounds.
struct ClampedCenterLayout: Layout {
    var centerX: CGFloat

    var animatableData: CGFloat {
        get { centerX }
        set { centerX = newValue }
    }

    nonisolated static func clampedCenter(_ centerX: CGFloat, labelWidth: CGFloat, width: CGFloat) -> CGFloat {
        let half = labelWidth / 2
        guard labelWidth < width else { return width / 2 }
        return min(max(centerX, half), width - half)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let size = subviews.first?.sizeThatFits(.unspecified) ?? .zero
        return CGSize(width: proposal.width ?? size.width, height: proposal.height ?? size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let subview = subviews.first else { return }
        let size = subview.sizeThatFits(.unspecified)
        let labelX = Self.clampedCenter(centerX, labelWidth: size.width, width: bounds.width)
        subview.place(
            at: CGPoint(x: bounds.minX + labelX, y: bounds.midY), anchor: .center, proposal: ProposedViewSize(size))
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
