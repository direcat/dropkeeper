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
}
