import DropKeeperCore
import Foundation
import Testing

@testable import DropKeeper

struct AutoHideTimerTests {
    @Test func timerExpiresAfterDuration() {
        var timer = AutoHideTimer(duration: 30)
        let now = Date()
        timer.start(now: now)
        #expect(!timer.isDue(now: now + 29) && timer.isDue(now: now + 30))
    }

    @Test func pauseKeepsRemaining() {
        var timer = AutoHideTimer(duration: 30)
        let now = Date()
        timer.start(now: now)
        timer.pause(now: now + 10)
        #expect(timer.isPaused && !timer.isDue(now: now + 100))
        timer.resume(now: now + 100)
        #expect(timer.remaining(now: now + 100) == 20)
        #expect(timer.isDue(now: now + 120))
    }

    @Test func restartGivesFullTime() {
        var timer = AutoHideTimer(duration: 30)
        let now = Date()
        timer.start(now: now)
        timer.restart(now: now + 25)
        #expect(timer.remaining(now: now + 25) == 30)
    }

    @Test func restartWhilePausedKeepsItPausedWithFullTime() {
        var timer = AutoHideTimer(duration: 30)
        let now = Date()
        timer.start(now: now)
        timer.pause(now: now + 10)
        timer.restart(now: now + 50)
        #expect(timer.isPaused && timer.remaining(now: now + 60) == 30)
    }

    @Test func neverDoesNothing() {
        var timer = AutoHideTimer(duration: Settings.notificationTimeoutNever)
        let now = Date()
        timer.start(now: now)
        timer.pause(now: now)
        timer.resume(now: now)
        #expect(timer.remaining(now: now) == nil && !timer.isDue(now: .distantFuture))
        #expect(timer.expiresAt == nil && !timer.isPaused)
    }

    @Test func stopClearsTheCountdown() {
        var timer = AutoHideTimer(duration: 30)
        timer.start(now: Date())
        timer.stop()
        #expect(timer.remaining(now: Date()) == nil && timer.expiresAt == nil)
    }
}
