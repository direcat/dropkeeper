import AppKit
import SwiftUI

/// Borderless, non-activating panel above the menu bar. It never takes focus by itself;
/// a click inside makes it key so the prompt's keyboard shortcuts work.
final class FloatingPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        // Just above the menu bar and its status items.
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        acceptsMouseMovedEvents = true
        animationBehavior = .none
        isReleasedWhenClosed = false
    }

    /// The frame a running slide or resize is heading for; nil when no frame animation is in flight. Decisions about
    /// the panel's frame are made against `settledFrame`, never the interpolated mid-animation `frame`.
    private(set) var frameTarget: CGRect?
    private var frameAnimation = 0

    var settledFrame: CGRect { frameTarget ?? frame }

    /// Forgets any running frame animation (the panel is going away), so a stale target or completion can't act on
    /// the next show.
    func resetFrameAnimation() {
        frameAnimation += 1
        frameTarget = nil
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

extension FloatingPanel {
    /// Shows the panel under the menu bar: it is placed at its start frame while still invisible, then slides down
    /// to `frame` while it fades in. Reduce Motion: no slide, a plain fade. Never animates from a stale frame.
    func slideIn(to frame: CGRect, reduceMotion: Bool, makeKey: Bool = false) {
        alphaValue = 0
        setFrame(reduceMotion ? frame : PanelGeometry.slideStartFrame(for: frame), display: true)
        if makeKey { makeKeyAndOrderFront(nil) } else { orderFrontRegardless() }
        animate(
            to: frame, moves: !reduceMotion,
            duration: reduceMotion ? TK.Motion.panelReducedFadeDuration : TK.Motion.panelSlideDuration)
    }

    /// Moves a visible panel to `frame` (same left and top edge: a resize in place) and back to full opacity. A
    /// running slide or resize is re-targeted through the animator, never overridden by a direct `setFrame`.
    func retarget(to frame: CGRect, reduceMotion: Bool) {
        if reduceMotion, frameTarget == nil { setFrame(frame, display: true) }
        animate(to: frame, moves: !reduceMotion || frameTarget != nil, duration: TK.Motion.panelResizeDuration)
    }

    /// Sets the frame without animation, unless a frame animation is in flight (then it is re-targeted).
    func place(_ frame: CGRect) {
        if frameTarget == nil { setFrame(frame, display: true) } else { animate(to: frame, moves: true, duration: 0.1) }
    }

    private func animate(to frame: CGRect, moves: Bool, duration: Double) {
        frameAnimation += 1
        let animation = frameAnimation
        if moves { frameTarget = frame }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
            if moves { animator().setFrame(frame, display: true) }
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.frameAnimation == animation else { return }
                self.frameTarget = nil
            }
        }
    }
}

/// The panel never becomes key on its own, so the first click in it would only make it key. Taking the first
/// mouse lets that click reach the content (e.g. a timeline stop), not just buttons.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    /// Called when the pointer enters (true) or leaves (false) the view, whichever app is active.
    var onPointerChange: ((Bool) -> Void)?

    /// Called when SwiftUI's content changed size, so the owner can resize the panel around it.
    var onIntrinsicSizeChange: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        onIntrinsicSizeChange?()
    }

    /// Our own area only: the hosting view's other areas drive SwiftUI's `.onHover`.
    private var pointerArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerArea { removeTrackingArea(pointerArea) }
        let area = NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        pointerArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        if event.trackingArea === pointerArea { onPointerChange?(true) }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        if event.trackingArea === pointerArea { onPointerChange?(false) }
    }
}
