import AppKit
import SwiftUI

/// Shows, moves and hides the single floating panel (prompt, notice, closed notch, hover list).
@MainActor
final class PanelCoordinator {
    private let model: AppModel
    private let actions: AppActions
    private let statusAnchor: @MainActor () -> CGRect?
    private let panel = FloatingPanel()
    private var hosting: NSHostingView<PanelRootView>?
    private var hovering = false
    /// False from the moment a hide starts; a show during the fade-out sets it again and keeps the panel.
    private var wantsVisible = false
    private var collapseTask: Task<Void, Never>?
    private var screenObserver: NSObjectProtocol?

    init(model: AppModel, actions: AppActions, statusAnchor: @escaping @MainActor () -> CGRect?) {
        self.model = model
        self.actions = actions
        self.statusAnchor = statusAnchor
    }

    func start() {
        ObservationLoop.run(
            { [weak self] in self?.readState() },
            onChange: { [weak self] in self?.render() })
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.render() } }
        render()
    }

    /// Everything that changes which content is shown, or the panel size. The countdown is not here: the hosted
    /// view observes it itself, and it never changes the frame.
    private func readState() {
        _ = model.isPromptAvailable
        _ = model.queue.items.count
        _ = model.queue.current?.id
        _ = model.notice.isVisible
        _ = model.notice.files.count
        _ = model.scheduled.count
        _ = model.settings.promptPresentation
        _ = model.settings.quietMode
    }

    func render() {
        let target = PresentationResolver.resolve(
            model.settings.promptPresentation, screens: ScreenDescriptor.current())
        let content = PanelDecision.content(
            promptAvailable: model.isPromptAvailable, noticeVisible: model.notice.isVisible, target: target,
            scheduledCount: model.scheduled.count, hovering: hovering)
        if !PanelDecision.keepsHover(showing: content) { resetHover() }
        guard content != .hidden else {
            hide()
            return
        }
        var isNotch = false
        var notchWidth: CGFloat = 0
        if case .notch(let screen) = target, let notch = screen.notchRect {
            isNotch = true
            notchWidth = notch.width
        }
        let root = PanelRootView(
            model: model, content: content, isNotch: isNotch, notchWidth: notchWidth, actions: actions,
            onHover: { [weak self] inside in self?.setHovering(inside) })
        let hostingView: NSHostingView<PanelRootView>
        if let hosting {
            hosting.rootView = root
            hostingView = hosting
        } else {
            hostingView = NSHostingView(rootView: root)
            panel.contentView = hostingView
            hosting = hostingView
        }
        guard let frame = frame(for: content, target: target, fitting: hostingView.fittingSize) else {
            hide()
            return
        }
        show(frame: frame)
    }

    private func frame(for content: PanelContent, target: PresentationTarget, fitting: CGSize) -> CGRect? {
        let size = CGSize(width: TK.Size.notchPanelWidth, height: max(fitting.height, 32))
        switch target {
        case .notch(let screen):
            guard let notch = screen.notchRect else { return nil }
            if content == .idle { return NotchGeometry.idleFrame(notch: notch) }
            return NotchGeometry.panelFrame(notch: notch, screenFrame: screen.frame, size: size)
        case .menuBar:
            let screens = ScreenDescriptor.current()
            let anchor = statusAnchor() ?? fallbackAnchor(screens)
            let screen = screens.first { $0.frame.contains(CGPoint(x: anchor.midX, y: anchor.midY)) } ?? screens.first
            guard let screen else { return nil }
            return NotchGeometry.menuBarPanelFrame(anchor: anchor, visibleFrame: screen.visibleFrame, size: size)
        }
    }

    private func fallbackAnchor(_ screens: [ScreenDescriptor]) -> CGRect {
        let frame = screens.first?.frame ?? .zero
        return CGRect(x: frame.maxX - 40, y: frame.maxY - 24, width: 24, height: 24)
    }

    private func show(frame: CGRect) {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        wantsVisible = true
        if panel.isVisible {
            guard frame != panel.frame || panel.alphaValue < 1 else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = reduceMotion ? 0 : 0.3
                context.allowsImplicitAnimation = true
                panel.animator().setFrame(frame, display: true)
                // Undoes a fade-out that is still running.
                panel.animator().alphaValue = 1
            }
        } else {
            panel.setFrame(frame, display: true)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                panel.animator().alphaValue = 1
            }
        }
    }

    private func hide() {
        resetHover()
        guard panel.isVisible, wantsVisible else { return }
        wantsVisible = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.finishHide() }
        }
    }

    private func finishHide() {
        // A new render may have started showing the panel again during the fade.
        guard !wantsVisible else { return }
        panel.orderOut(nil)
    }

    private func resetHover() {
        collapseTask?.cancel()
        collapseTask = nil
        hovering = false
    }

    private func setHovering(_ inside: Bool) {
        collapseTask?.cancel()
        if inside {
            guard !hovering else { return }
            hovering = true
            render()
        } else {
            collapseTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled, let self else { return }
                self.hovering = false
                self.render()
            }
        }
    }
}
