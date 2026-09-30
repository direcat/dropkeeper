import SwiftUI

struct PanelRootView: View {
    @Bindable var model: AppModel
    let content: PanelContent
    let isNotch: Bool
    let notchWidth: CGFloat
    let actions: AppActions
    let onHover: (Bool) -> Void

    var body: some View {
        Group {
            switch content {
            case .prompt:
                if let file = model.queue.current {
                    PromptView(
                        file: file, stackCount: model.queue.items.count, timeline: $model.timeline,
                        applyToAll: $model.applyToAll, now: model.now,
                        onDone: { Task { await model.decide() } },
                        onKeep: { Task { await model.keepPrompted() } },
                        onClose: { model.dismissPrompt() })
                }
            case .notice:
                NoticeView(
                    files: model.notice.files, canUndo: model.settings.deleteMode == .trash,
                    onUndo: { Task { await model.undoNotice() } })
            case .idle:
                NotchIdleView(count: model.scheduled.count, urgentSeconds: model.urgentSeconds, notchWidth: notchWidth)
            case .idleExpanded:
                PendingListView(model: model, actions: actions, showsFooter: false)
            case .hidden:
                EmptyView()
            }
        }
        .background(TK.Notch.surface)
        .clipShape(shape)
        .environment(\.colorScheme, .dark)
        .onHover(perform: onHover)
    }

    private var shape: AnyShape {
        isNotch ? AnyShape(NotchShape()) : AnyShape(RoundedRectangle(cornerRadius: TK.Radius.notchBottom))
    }
}
