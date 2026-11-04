import CoreGraphics

enum PanelContent: Equatable {
    case hidden, prompt, notice, error
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
    /// Prompt beats notice. An error never hides the prompt or the notice (they show it as a banner); on its own
    /// it replaces a hidden panel.
    static func content(promptAvailable: Bool, noticeVisible: Bool, errorVisible: Bool) -> PanelContent {
        if promptAvailable { return .prompt }
        if noticeVisible { return .notice }
        return errorVisible ? .error : .hidden
    }

    /// Skips only a panel that is fully shown at the same frame. The window's alpha can't tell: a fade-out
    /// started in the same run-loop tick still reads 1.
    static func showStep(isOnScreen: Bool, isFadingOut: Bool, frameChanged: Bool) -> PanelShowStep {
        guard isOnScreen else { return .fadeIn }
        return isFadingOut || frameChanged ? .restore : .none
    }

    /// A prompt, notice or error stays where it opened while it is followed by another of them, so the panel
    /// stays under the menu bar anchor it opened with. After a hidden panel the anchor is taken again.
    static func keepsTarget(previous: PanelContent, next: PanelContent) -> Bool {
        isOpenContent(previous) && isOpenContent(next)
    }

    /// The menu bar anchor for `next`: the one the open panel started with while `keepsTarget` holds, otherwise the
    /// `current` one. The status item moves when other menu bar items come and go, and the open panel must not
    /// follow it (it would slide away from under the pointer).
    static func anchor(previous: PanelContent, next: PanelContent, locked: CGRect?, current: CGRect) -> CGRect {
        guard keepsTarget(previous: previous, next: next), let locked else { return current }
        return locked
    }

    private static func isOpenContent(_ content: PanelContent) -> Bool {
        content == .prompt || content == .notice || content == .error
    }
}
