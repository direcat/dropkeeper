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
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? TK.Motion.panelFadeInDuration : TK.Motion.panelSlideDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
            if !reduceMotion { animator().setFrame(frame, display: true) }
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
