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

    /// The list shows the error itself, so it also has it in the menu bar popover.
    @ViewBuilder
    private var banner: some View {
        if let message = model.panelError.message, content == .prompt || content == .notice || content == .error {
            PanelErrorBanner(message: message, standalone: content != .prompt)
        }
    }

    private func prompt(for file: TrackedFile) -> some View {
        PromptView(
            file: file, stackCount: model.queue.isRevisiting ? 1 : model.queue.items.count,
            duplicateOf: file.duplicateOf, timeline: $model.timeline,
            applyToAll: $model.applyToAll, now: model.now, hideProgress: nil, hideSeconds: nil,
            onDone: { Task { await model.decide(for: file.id) } },
            onKeep: { Task { await model.keepPrompted(for: file.id) } },
            onClose: { model.dismissPrompt() },
            onOpen: { FileOpener.open(FinderReveal.target(for: file.path)) },
            onDeleteDuplicate: { Task { await model.deleteDuplicate(for: file.id) } })
    }
}
