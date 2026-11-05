import AppKit
import DropKeeperCore
import SwiftUI

/// Shows, moves and hides the single floating panel (prompt, notice, error) under the menu bar icon.
@MainActor
final class PanelCoordinator {
    private let model: AppModel
    private let statusAnchor: @MainActor () -> CGRect?
    private let panel = FloatingPanel()
    private var hosting: FirstMouseHostingView<PanelRootView>?
    /// True from the start of a hide's fade until the panel is ordered out; a show in between clears it and keeps
    /// the panel.
    private var isFadingOut = false
    private var screenObserver: NSObjectProtocol?
    /// What the panel showed last.
    private var lastContent = PanelContent.hidden
    /// The menu bar anchor a prompt, notice or error opened with (see `PanelDecision.anchor`).
    private var lockedAnchor: CGRect?
    private var keyMonitor: Any?

    init(model: AppModel, statusAnchor: @escaping @MainActor () -> CGRect?) {
        self.model = model
        self.statusAnchor = statusAnchor
    }

    isolated deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
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
                self?.lockedAnchor = nil
                self?.render()
            }
        }
        // Any key pressed in the panel (arrows, Tab, Space...) shows the user is still at the prompt.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated {
                if let self, event.window === self.panel { self.model.noteKeyActivity() }
            }
            return event
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
        _ = model.notice.items.count
        _ = model.ruleNotice.isVisible
        _ = model.ruleNotice.items.count
        _ = model.reminders.due.count
        _ = model.panelError.message
        _ = model.settings.quietMode
        _ = model.isListOpen
    }

    func render() {
        // One card at a time: while the menu bar list is open it is the only card (it shows errors itself), and
        // `isPromptAvailable` is already false then.
        let listOpen = model.isListOpen
        let content = PanelDecision.content(
            promptAvailable: model.isPromptAvailable, noticeVisible: model.isNoticeVisible && !listOpen,
            errorVisible: model.panelError.isVisible && !listOpen)
        let previousContent = lastContent
        lastContent = content
        guard content != .hidden else {
            lockedAnchor = nil
            model.resumePanelTimers()  // no exit event arrives for a panel that goes away under the pointer
            hide()
            return
        }
        let root = PanelRootView(model: model, content: content)
        let hostingView: FirstMouseHostingView<PanelRootView>
        if let hosting {
            hosting.rootView = root
            hostingView = hosting
        } else {
            hostingView = FirstMouseHostingView(rootView: root)
            hostingView.onPointerChange = { [weak self] inside in
                if inside { self?.model.pausePanelTimers() } else { self?.model.resumePanelTimers() }
            }
            // The coordinator sizes the panel itself. Keep the intrinsic size (fittingSize needs it) but
            // drop SwiftUI's window min/max constraints.
            hostingView.sizingOptions = [.intrinsicContentSize]
            panel.contentView = hostingView
            hosting = hostingView
        }
        guard let frame = frame(for: content, previous: previousContent, fitting: hostingView.fittingSize) else {
            lastContent = .hidden
            lockedAnchor = nil
            model.resumePanelTimers()
            hide()
            return
        }
        show(frame: frame)
    }

    private func frame(for content: PanelContent, previous: PanelContent, fitting: CGSize) -> CGRect? {
        let size = CGSize(width: TK.Size.panelWidth, height: max(fitting.height, 32))
        let screens = ScreenDescriptor.current()
        let anchor = PanelDecision.anchor(
            previous: previous, next: content, locked: lockedAnchor,
            current: statusAnchor() ?? fallbackAnchor(screens))
        lockedAnchor = anchor
        let screen = screens.first { $0.frame.contains(CGPoint(x: anchor.midX, y: anchor.midY)) } ?? screens.first
        guard let screen else { return nil }
        return PanelGeometry.menuBarPanelFrame(anchor: anchor, visibleFrame: screen.visibleFrame, size: size)
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
            // A visible panel resizes in place; any other move (new anchor) jumps instead of travelling.
            let animated = !reduceMotion && PanelGeometry.resizesInPlace(from: panel.frame, to: frame)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = animated ? TK.Motion.panelResizeDuration : 0
                context.allowsImplicitAnimation = animated
                if animated {
                    panel.animator().setFrame(frame, display: true)
                } else {
                    panel.setFrame(frame, display: true)
                }
                // Undoes a fade-out that is still running.
                panel.animator().alphaValue = 1
            }
            syncPointer(frame: frame)
        case .fadeIn:
            panel.slideIn(to: frame, reduceMotion: reduceMotion)
            syncPointer(frame: frame)
        }
    }

    /// A panel that appears, grows or shrinks under a resting pointer gets no enter or exit event, so the
    /// countdowns follow where the pointer is instead.
    private func syncPointer(frame: CGRect) {
        if frame.contains(NSEvent.mouseLocation) { model.pausePanelTimers() } else { model.resumePanelTimers() }
    }

    private func hide() {
        guard panel.isVisible, !isFadingOut else { return }
        isFadingOut = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = TK.Motion.panelFadeOutDuration
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
}
