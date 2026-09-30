enum PanelContent: Equatable {
    case hidden, prompt, notice, idle, idleExpanded
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
    static func keepsHover(showing content: PanelContent) -> Bool {
        content == .idle || content == .idleExpanded
    }
}
