import CoreGraphics

enum PanelContent: Equatable {
    case hidden, prompt, notice, idle, idleExpanded, error
}

/// What `show` does with the panel.
enum PanelShowStep: Equatable {
    /// Not on screen: place it and fade in.
    case fadeIn
    /// On screen: animate to the frame and back to full opacity (this also undoes a running fade-out).
    case restore
    /// Already shown at that frame.
    case none
}

enum PanelDecision {
    /// Prompt beats notice; the closed-notch indicator exists only for the notch target with scheduled files.
    /// An error never hides the prompt, the notice or the open list (they show it as a banner); on its own it
    /// replaces the closed notch or a hidden panel.
    static func content(
        promptAvailable: Bool, noticeVisible: Bool, errorVisible: Bool = false, target: PresentationTarget,
        scheduledCount: Int, hovering: Bool
    ) -> PanelContent {
        if promptAvailable { return .prompt }
        if noticeVisible { return .notice }
        let hasIdle: Bool
        if case .notch = target, scheduledCount > 0 { hasIdle = true } else { hasIdle = false }
        if hasIdle && hovering { return .idleExpanded }
        if errorVisible { return .error }
        return hasIdle ? .idle : .hidden
    }

    /// Hover only matters for the closed notch. Any other content (or a hidden panel) resets it, because a panel
    /// ordered out under the pointer never gets the mouse-exit event.
    /// Skips only a panel that is fully shown at the same frame. The window's alpha can't tell: a fade-out
    /// started in the same run-loop tick still reads 1.
    static func showStep(isOnScreen: Bool, isFadingOut: Bool, frameChanged: Bool) -> PanelShowStep {
        guard isOnScreen else { return .fadeIn }
        return isFadingOut || frameChanged ? .restore : .none
    }

    /// In the notch the panel hangs from the top screen edge: open content starts below the hardware cutout.
    /// The closed notch lays itself out around the cutout. `notchHeight` is nil for the menu bar panel.
    static func topInset(for content: PanelContent, notchHeight: CGFloat?) -> CGFloat {
        guard let notchHeight else { return 0 }
        switch content {
        case .prompt, .notice, .idleExpanded, .error: return notchHeight
        case .idle, .hidden: return 0
        }
    }

    static func keepsHover(showing content: PanelContent) -> Bool {
        content == .idle || content == .idleExpanded
    }

    /// A prompt, notice or error stays where it opened while it is followed by another of them, so the panel
    /// doesn't jump when the pointer crosses displays. After a hidden or idle panel the target is resolved again;
    /// the closed notch and its list use the idle target.
    static func keepsTarget(previous: PanelContent, next: PanelContent) -> Bool {
        isOpenContent(previous) && isOpenContent(next)
    }

    /// The target for `next`: the locked one while `keepsTarget` holds and its display is still connected (with
    /// fresh geometry), otherwise `resolved`.
    static func target(
        previous: PanelContent, next: PanelContent, locked: PresentationTarget?, resolved: PresentationTarget,
        screens: [ScreenDescriptor]
    ) -> PresentationTarget {
        guard keepsTarget(previous: previous, next: next), let locked else { return resolved }
        switch locked {
        case .menuBar:
            return .menuBar
        case .notch(let screen):
            let current = PresentationResolver.notchedScreens(screens).first { $0.id == screen.id }
            return current.map(PresentationTarget.notch) ?? resolved
        }
    }

    private static func isOpenContent(_ content: PanelContent) -> Bool {
        content == .prompt || content == .notice || content == .error
    }
}
