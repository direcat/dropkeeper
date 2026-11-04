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

enum RingProgress {
    /// The part of the timer that is left, 0…1; 0 without an expiry or length. After Extend the remaining time
    /// can exceed the old length, so it is clamped.
    static func share(for file: TrackedFile, now: Date) -> Double {
        guard let expiresAt = file.expiresAt, let length = file.timerLength, length > 0 else { return 0 }
        return min(max(expiresAt.timeIntervalSince(now) / length, 0), 1)
    }

    /// The last seconds, or less than a tenth of the timer.
    static func isWarning(for file: TrackedFile, now: Date) -> Bool {
        guard let expiresAt = file.expiresAt else { return false }
        return expiresAt.timeIntervalSince(now) <= Double(TK.Motion.urgentThresholdSeconds)
            || share(for: file, now: now) < warningShare
    }

    private static let warningShare = 0.1
}
