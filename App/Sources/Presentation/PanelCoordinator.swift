import AppKit
import DropKeeperCore
import SwiftUI

/// Shows, moves and hides the single floating panel (prompt, notice, closed notch, hover list).
@MainActor
final class PanelCoordinator {
    private let model: AppModel
    private let actions: AppActions
    private let statusAnchor: @MainActor () -> CGRect?
    /// The open popover shows errors in its list; the panel then doesn't show them a second time.
    private let isPopoverShown: @MainActor () -> Bool
    private let panel = FloatingPanel()
    private var hosting: NSHostingView<PanelRootView>?
    private var hovering = false
    /// True from the start of a hide's fade until the panel is ordered out; a show in between clears it and keeps
    /// the panel.
    private var isFadingOut = false
    private var collapseTask: Task<Void, Never>?
    private var screenObserver: NSObjectProtocol?
    /// What the panel showed last, and where a prompt, notice or error opened (see `PanelDecision.target`).
    private var lastContent = PanelContent.hidden
    private var lockedTarget: PresentationTarget?
    private var lockedSetting: PromptPresentation?
    /// The menu bar anchor a prompt, notice or error opened with (see `PanelDecision.anchor`).
    private var lockedAnchor: CGRect?

    init(
        model: AppModel, actions: AppActions, statusAnchor: @escaping @MainActor () -> CGRect?,
        isPopoverShown: @escaping @MainActor () -> Bool
    ) {
        self.model = model
        self.actions = actions
        self.statusAnchor = statusAnchor
        self.isPopoverShown = isPopoverShown
    }

    func start() {
        ObservationLoop.run(
            { [weak self] in self?.readState() },
            onChange: { [weak self] in self?.render() })
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                // New display layout: place an open panel again.
                self?.lockedTarget = nil
                self?.lockedAnchor = nil
                self?.render()
            }
        }
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
        _ = model.panelError.message
        _ = model.scheduled.count
        _ = model.settings.promptPresentation
        _ = model.settings.quietMode
    }

    func render() {
        let setting = model.settings.promptPresentation
        let screens = ScreenDescriptor.current()
        let idleTarget = PresentationResolver.idleTarget(setting, screens: screens)
        let content = PanelDecision.content(
            promptAvailable: model.isPromptAvailable, noticeVisible: model.notice.isVisible,
            errorVisible: model.panelError.isVisible && !isPopoverShown(), target: idleTarget,
            scheduledCount: model.scheduled.count, hovering: hovering)
        let previousContent = lastContent
        let target = presentationTarget(
            for: content, setting: setting, idleTarget: idleTarget, screens: screens)
        lastContent = content
        if !PanelDecision.keepsHover(showing: content) { resetHover() }
        guard content != .hidden else {
            hide()
            return
        }
        var isNotch = false
        var notchWidth: CGFloat = 0
        var notchHeight: CGFloat?
        if case .notch(let screen) = target, let notch = screen.notchRect {
            isNotch = true
            notchWidth = notch.width
            notchHeight = notch.height
        }
        let root = PanelRootView(
            model: model, content: content, isNotch: isNotch, notchWidth: notchWidth,
            topInset: PanelDecision.topInset(for: content, notchHeight: notchHeight), actions: actions,
            onHover: { [weak self] inside in self?.setHovering(inside) })
        let hostingView: NSHostingView<PanelRootView>
        if let hosting {
            hosting.rootView = root
            hostingView = hosting
        } else {
            hostingView = NSHostingView(rootView: root)
            // The coordinator sizes the panel itself. Keep the intrinsic size (fittingSize needs it) but
            // drop SwiftUI's window min/max constraints, which shrank the closed notch to its content height.
            hostingView.sizingOptions = [.intrinsicContentSize]
            panel.contentView = hostingView
            hosting = hostingView
        }
        guard
            let frame = frame(
                for: content, previous: previousContent, target: target, fitting: hostingView.fittingSize)
        else {
            lastContent = .hidden
            lockedTarget = nil
            lockedAnchor = nil
            hide()
            return
        }
        show(frame: frame)
    }

    /// The closed notch uses the idle target; a prompt, notice or error keeps the target it opened with.
    private func presentationTarget(
        for content: PanelContent, setting: PromptPresentation, idleTarget: PresentationTarget,
        screens: [ScreenDescriptor]
    ) -> PresentationTarget {
        if content == .idle || content == .idleExpanded || content == .hidden {
            lockedTarget = nil
            lockedAnchor = nil
            return idleTarget
        }
        let target = PanelDecision.target(
            previous: lastContent, next: content, locked: lockedSetting == setting ? lockedTarget : nil,
            resolved: PresentationResolver.resolve(setting, screens: screens), screens: screens)
        lockedTarget = target
        lockedSetting = setting
        return target
    }

    private func frame(
        for content: PanelContent, previous: PanelContent, target: PresentationTarget, fitting: CGSize
    ) -> CGRect? {
        let size = CGSize(width: TK.Size.notchPanelWidth, height: max(fitting.height, 32))
        switch target {
        case .notch(let screen):
            lockedAnchor = nil
            guard let notch = screen.notchRect else { return nil }
            if content == .idle { return NotchGeometry.idleFrame(notch: notch) }
            return NotchGeometry.panelFrame(notch: notch, screenFrame: screen.frame, size: size)
        case .menuBar:
            let screens = ScreenDescriptor.current()
            let anchor = PanelDecision.anchor(
                previous: previous, next: content, locked: lockedAnchor,
                current: statusAnchor() ?? fallbackAnchor(screens))
            lockedAnchor = anchor
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
        let step = PanelDecision.showStep(
            isOnScreen: panel.isVisible, isFadingOut: isFadingOut, frameChanged: frame != panel.frame)
        isFadingOut = false
        switch step {
        case .none:
            return
        case .restore:
            NSAnimationContext.runAnimationGroup { context in
                context.duration = reduceMotion ? 0 : 0.3
                context.allowsImplicitAnimation = true
                panel.animator().setFrame(frame, display: true)
                // Undoes a fade-out that is still running.
                panel.animator().alphaValue = 1
            }
        case .fadeIn:
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
        guard panel.isVisible, !isFadingOut else { return }
        isFadingOut = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.finishHide() }
        }
    }

    private func finishHide() {
        // A new render may have started showing the panel again during the fade.
        guard isFadingOut else { return }
        isFadingOut = false
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
