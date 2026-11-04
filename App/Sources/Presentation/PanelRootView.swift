import SwiftUI

struct PanelRootView: View {
    @Bindable var model: AppModel
    let content: PanelContent

    var body: some View {
        VStack(spacing: 0) {
            banner
            main
        }
        .background(TK.Notch.surface)
        .clipShape(RoundedRectangle(cornerRadius: TK.Radius.notchBottom))
        .environment(\.colorScheme, .dark)
    }

    /// The list shows the error itself, so it also has it in the menu bar popover.
    @ViewBuilder
    private var banner: some View {
        if let message = model.panelError.message, content == .prompt || content == .notice || content == .error {
            PanelErrorBanner(message: message, standalone: content == .error)
        }
    }

    @ViewBuilder
    private var main: some View {
        switch content {
        case .prompt:
            if let file = model.queue.current {
                if model.isNoticeVisible {
                    NoticeStackView(model: model, holdsNotice: false)
                    Rectangle().fill(TK.Notch.hairline).frame(height: 1)
                }
                PromptView(
                    file: file, stackCount: model.queue.isRevisiting ? 1 : model.queue.items.count,
                    duplicateOf: file.duplicateOf, timeline: $model.timeline,
                    applyToAll: $model.applyToAll, now: model.now,
                    onDone: { Task { await model.decide(for: file.id) } },
                    onKeep: { Task { await model.keepPrompted(for: file.id) } },
                    onClose: { model.dismissPrompt() },
                    onOpen: { FileOpener.open(FinderReveal.target(for: file.path)) },
                    onDeleteDuplicate: { Task { await model.deleteDuplicate(for: file.id) } })
            }
        case .notice:
            NoticeStackView(model: model, holdsNotice: true)
        case .hidden, .error:
            EmptyView()
        }
    }
}
