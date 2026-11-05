import DropKeeperCore
import SwiftUI

struct PanelRootView: View {
    @Bindable var model: AppModel
    let content: PanelContent

    var body: some View {
        // Notice cards are their own glass cards, stacked above the prompt's card.
        VStack(spacing: TK.Space.s) {
            switch content {
            case .prompt:
                if model.queue.current != nil, model.isNoticeVisible {
                    NoticeStackView(model: model, holdsNotice: false)
                }
                if let file = model.queue.current {
                    GlassCard {
                        VStack(spacing: 0) {
                            banner
                            prompt(for: file)
                        }
                    }
                }
            case .notice:
                if model.panelError.message != nil { GlassCard { banner } }
                NoticeStackView(model: model, holdsNotice: true)
            case .error:
                GlassCard { banner }
            case .hidden:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var banner: some View {
        if let message = model.panelError.message {
            PanelErrorBanner(message: message, standalone: content != .prompt)
        }
    }

    /// The bar and the caption follow the model's countdown, so the view ticks by itself: once a second while a
    /// countdown runs, never otherwise (the bar is a coarse indicator, and a slow tick keeps the CPU idle).
    private func prompt(for file: TrackedFile) -> some View {
        SwiftUI.TimelineView(HideTickSchedule(isRunning: model.promptHideProgress != nil)) { _ in
            promptView(for: file)
        }
    }

    private func promptView(for file: TrackedFile) -> some View {
        PromptView(
            file: file, stackCount: model.queue.isRevisiting ? 1 : model.queue.items.count,
            duplicateOf: file.duplicateOf, timeline: $model.timeline,
            applyToAll: $model.applyToAll, now: model.now, hideProgress: model.promptHideProgress,
            hideSeconds: model.promptHideSeconds,
            onDone: { Task { await model.decide(for: file.id) } },
            onKeep: { Task { await model.keepPrompted(for: file.id) } },
            onClose: { model.dismissPrompt() },
            onOpen: { FileOpener.open(FinderReveal.target(for: file.path)) },
            onDeleteDuplicate: { Task { await model.deleteDuplicate(for: file.id) } })
    }
}

/// One tick a second while the prompt counts down; a single entry (no ticking) when it doesn't.
struct HideTickSchedule: TimelineSchedule {
    let isRunning: Bool

    func entries(from start: Date, mode: Mode) -> AnyIterator<Date> {
        var next: Date? = start
        return AnyIterator {
            guard let current = next else { return nil }
            next = isRunning ? current.addingTimeInterval(TK.Motion.hideTick) : nil
            return current
        }
    }
}
