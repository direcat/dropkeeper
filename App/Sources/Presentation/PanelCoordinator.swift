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
    /// The pending re-measure of a content that had not laid out yet (see `render`).
    private var retryWork: DispatchWorkItem?

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

    func render(retryTinyMeasurement: Bool = true) {
        // One card at a time: while the menu bar list is open it is the only card (it shows errors itself), and
        // `isPromptAvailable` is already false then.
        let listOpen = model.isListOpen
        let content = PanelDecision.content(
            promptAvailable: model.isPromptAvailable, noticeVisible: model.isNoticeVisible && !listOpen,
            errorVisible: model.panelError.isVisible && !listOpen)
        let previousContent = lastContent
        lastContent = content
        guard content != .hidden else {
            retryWork?.cancel()
            retryWork = nil
            lockedAnchor = nil
            model.resumePanelTimers()  // no exit event arrives for a panel that goes away under the pointer
            if panel.isVisible { hide() } else { dropContent() }
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
            // A measurement taken before the content laid out heals when its real size arrives.
            hostingView.onIntrinsicSizeChange = { [weak self] in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.reframe() } }
            }
            panel.contentView = hostingView
            hosting = hostingView
        }
        hostingView.layoutSubtreeIfNeeded()
        let fitting = hostingView.fittingSize
        if fitting.height < TK.Motion.panelMinMeasuredHeight, retryTinyMeasurement {
            // The new content has not laid out yet: measure again on the next turn rather than show a sliver.
            retryWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated { self?.render(retryTinyMeasurement: false) }
            }
            retryWork = work
            DispatchQueue.main.async(execute: work)
            return
        }
        guard let frame = frame(for: content, previous: previousContent, fitting: fitting) else {
            lastContent = .hidden
            lockedAnchor = nil
            model.resumePanelTimers()
            hide()
            return
        }
        show(frame: frame)
    }

    /// Places the open panel again after its content changed size, without touching the content.
    private func reframe() {
        guard lastContent != .hidden, let hosting, panel.isVisible, !isFadingOut else { return }
        hosting.layoutSubtreeIfNeeded()
        let fitting = hosting.fittingSize
        guard fitting.height >= TK.Motion.panelMinMeasuredHeight,
            let frame = frame(for: lastContent, previous: lastContent, fitting: fitting)
        else { return }
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
        guard panel.isVisible else {
            isFadingOut = false
            panel.slideIn(to: frame, reduceMotion: reduceMotion)
            syncPointer(frame: frame)
            return
        }
        let wasFadingOut = isFadingOut
        isFadingOut = false
        switch PanelDecision.frameStep(settled: panel.settledFrame, new: frame) {
        case .keep:
            guard wasFadingOut else { return }
            panel.retarget(to: frame, reduceMotion: reduceMotion)  // undoes the running fade-out
        case .resize:
            panel.retarget(to: frame, reduceMotion: reduceMotion)
        case .slideIn:
            panel.slideIn(to: frame, reduceMotion: reduceMotion)
        }
        syncPointer(frame: frame)
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
        dropContent()
    }

    /// No hidden view graph keeps running (ring timelines), and the next show measures a fresh one.
    private func dropContent() {
        panel.resetFrameAnimation()
        hosting = nil
        panel.contentView = nil
    }
}
