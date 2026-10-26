import SwiftUI

struct PanelRootView: View {
    @Bindable var model: AppModel
    let content: PanelContent
    let isNotch: Bool
    let notchWidth: CGFloat
    /// Keeps open content below the hardware notch (`PanelDecision.topInset`); part of the fitting size.
    var topInset: CGFloat = 0
    let actions: AppActions
    let onHover: (Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            banner
            main
        }
        .padding(.top, topInset)
        // The closed notch is taller than its content: fill the panel the coordinator sized.
        .frame(maxWidth: content == .idle ? .infinity : nil, maxHeight: content == .idle ? .infinity : nil)
        .background(TK.Notch.surface)
        .clipShape(shape)
        .environment(\.colorScheme, .dark)
        .onHover(perform: onHover)
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
                PromptView(
                    file: file, stackCount: model.queue.items.count, timeline: $model.timeline,
                    applyToAll: $model.applyToAll, now: model.now,
                    onDone: { Task { await model.decide(for: file.id) } },
                    onKeep: { Task { await model.keepPrompted(for: file.id) } },
                    onClose: { model.dismissPrompt() },
                    onOpen: { FileOpener.open(FinderReveal.target(for: file.path)) })
            }
        case .notice:
            NoticeView(
                files: model.notice.items, canUndo: model.settings.deleteMode == .trash,
                onUndo: { Task { await model.undoNotice() } })
        case .idle:
            NotchIdleView(count: model.scheduled.count, urgentSeconds: model.urgentSeconds, notchWidth: notchWidth)
        case .idleExpanded:
            PendingListView(model: model, actions: actions, showsFooter: false)
        case .hidden, .error:
            EmptyView()
        }
    }

    private var shape: AnyShape {
        isNotch ? AnyShape(NotchShape()) : AnyShape(RoundedRectangle(cornerRadius: TK.Radius.notchBottom))
    }
}
