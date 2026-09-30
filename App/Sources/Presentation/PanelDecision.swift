enum PanelContent: Equatable {
    case hidden, prompt, notice, idle, idleExpanded
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
    static func content(
        promptAvailable: Bool, noticeVisible: Bool, target: PresentationTarget, scheduledCount: Int, hovering: Bool
    ) -> PanelContent {
        if promptAvailable { return .prompt }
        if noticeVisible { return .notice }
        guard case .notch = target, scheduledCount > 0 else { return .hidden }
        return hovering ? .idleExpanded : .idle
    }

    /// Hover only matters for the closed notch. Any other content (or a hidden panel) resets it, because a panel
    /// ordered out under the pointer never gets the mouse-exit event.
    /// Skips only a panel that is fully shown at the same frame. The window's alpha can't tell: a fade-out
    /// started in the same run-loop tick still reads 1.
    static func showStep(isOnScreen: Bool, isFadingOut: Bool, frameChanged: Bool) -> PanelShowStep {
        guard isOnScreen else { return .fadeIn }
        return isFadingOut || frameChanged ? .restore : .none
    }

    static func keepsHover(showing content: PanelContent) -> Bool {
        content == .idle || content == .idleExpanded
    }
}
