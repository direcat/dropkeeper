import DropKeeperCore
import SwiftUI

/// A ring that shows how much of a timer is left, with a view (the file icon) in its center.
struct ProgressRing<Center: View>: View {
    let progress: Double
    let tint: Color
    @ViewBuilder let center: Center

    init(progress: Double, tint: Color, @ViewBuilder center: () -> Center) {
        self.progress = progress
        self.tint = tint
        self.center = center()
    }

    var body: some View {
        ZStack {
            Circle().inset(by: TK.Size.ringLine / 2).stroke(TK.Palette.fill, lineWidth: TK.Size.ringLine)
            Circle()
                .inset(by: TK.Size.ringLine / 2)
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: TK.Size.ringLine, lineCap: .round))
                .rotationEffect(.degrees(-90))
            center
        }
        .frame(width: TK.Size.ring, height: TK.Size.ring)
    }
}

/// A color stop of the progress ring.
enum RingStop: Hashable { case green, amber, red }

enum RingProgress {
    /// The part of the timer that is left, 0…1; 0 without an expiry or length. After Extend the remaining time
    /// can exceed the old length, so it is clamped.
    static func share(for file: TrackedFile, now: Date) -> Double {
        guard let expiresAt = file.expiresAt, let length = file.timerLength, length > 0 else { return 0 }
        return min(max(expiresAt.timeIntervalSince(now) / length, 0), 1)
    }

    /// How often a ring needs a redraw to run down smoothly: one step of `TK.Motion.ringStepPoints` of arc, within
    /// the tick limits, so a 30-day timer does not redraw at 30 fps.
    static func tickInterval(timerLength: TimeInterval) -> TimeInterval {
        let radius = (TK.Size.ring - TK.Size.ringLine) / 2
        let circumference = 2 * Double.pi * Double(radius)
        let interval = max(timerLength, 0) * Double(TK.Motion.ringStepPoints) / circumference
        return min(max(interval, TK.Motion.ringFastestTick), TK.Motion.ringSlowestTick)
    }

    /// The ring's color blend for a remaining share: green from half the time left, amber at a quarter, red from
    /// a twentieth, linear in between. `amount` is how far the blend has moved from `from` to `to`.
    struct Blend: Equatable {
        let from: RingStop
        let to: RingStop
        let amount: Double
    }

    static let greenShare = 0.5
    static let amberShare = 0.25
    static let redShare = 0.05

    static func blend(share: Double) -> Blend {
        let share = min(max(share, 0), 1)
        if share >= greenShare { return Blend(from: .green, to: .green, amount: 0) }
        if share >= amberShare {
            return Blend(from: .green, to: .amber, amount: (greenShare - share) / (greenShare - amberShare))
        }
        if share > redShare {
            return Blend(from: .amber, to: .red, amount: (amberShare - share) / (amberShare - redShare))
        }
        return Blend(from: .red, to: .red, amount: 0)
    }

    /// The ring's color for a remaining share (1 = all the time left, 0 = expired).
    static func tint(share: Double) -> Color {
        let blend = blend(share: share)
        return color(of: blend.from).mix(with: color(of: blend.to), by: blend.amount)
    }

    private static func color(of stop: RingStop) -> Color {
        switch stop {
        case .green: TK.Palette.ringGreen
        case .amber: TK.Palette.warning
        case .red: TK.Palette.destructive
        }
    }
}

/// A progress ring of a file's timer that runs down continuously. Only this small view re-renders on the fast
/// tick, not the list around it. The panels drop their content when hidden, so the timeline stops with it.
struct LiveRing<Center: View>: View {
    let file: TrackedFile
    @ViewBuilder let center: Center
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Without a timer length the share is constantly 0, so the slowest tick will do.
    private var interval: TimeInterval {
        guard let length = file.timerLength, length > 0 else { return TK.Motion.ringSlowestTick }
        return RingProgress.tickInterval(timerLength: length)
    }

    var body: some View {
        if reduceMotion {
            let reduced = max(interval, TK.Motion.ringReducedTick)
            SwiftUI.TimelineView(.periodic(from: .now, by: reduced)) { ring(at: $0.date) }
        } else {
            SwiftUI.TimelineView(.animation(minimumInterval: interval)) { ring(at: $0.date) }
        }
    }

    private func ring(at date: Date) -> some View {
        let share = RingProgress.share(for: file, now: date)
        return ProgressRing(progress: share, tint: RingProgress.tint(share: share)) { center }
    }
}
