import AppKit
import SwiftUI

/// Shows the menu bar list as a card under the status item: the same floating panel the prompt uses, so the glass
/// card is the whole surface (no popover frame or arrow). It closes like a transient popover did: on Esc, on a click
/// anywhere else, on another window taking over and when the app is deactivated.
@MainActor
final class ListPanelController {
    private let model: AppModel
    private let actions: AppActions
    /// The status item's frame (the card hangs under it) and its window (clicks there toggle, not dismiss).
    private let anchorFrame: @MainActor () -> CGRect?
    private let anchorWindow: @MainActor () -> NSWindow?
    private let panel = FloatingPanel()
    private var hosting: FirstMouseHostingView<PendingListView>?
    private var anchor = CGRect.zero
    private var monitors: [Any] = []
    private var deactivationObserver: NSObjectProtocol?
    /// Called after the list opened or closed, so the floating panel can step aside or come back.
    var onChange: (@MainActor () -> Void)?

    init(
        model: AppModel, actions: AppActions, anchorFrame: @escaping @MainActor () -> CGRect?,
        anchorWindow: @escaping @MainActor () -> NSWindow?
    ) {
        self.model = model
        self.actions = actions
        self.anchorFrame = anchorFrame
        self.anchorWindow = anchorWindow
    }

    isolated deinit {
        // The controller lives as long as the app; this only keeps a stray monitor from outliving it.
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        if let deactivationObserver { NotificationCenter.default.removeObserver(deactivationObserver) }
    }

    var isShown: Bool { panel.isVisible }

    func toggle() {
        if isShown { close() } else { show() }
    }

    func show() {
        guard !isShown, let frame = anchorFrame() else { return }
        anchor = frame
        // Activating the app makes ⌘, and ⌘Q from the main menu work while the card is key.
        AppActivation.activate()
        model.isListOpen = true
        // A fresh view each time, so the card opens on Upcoming.
        let root = PendingListView(model: model, actions: actions)
        let hostingView = FirstMouseHostingView(rootView: root)
        hostingView.sizingOptions = [.intrinsicContentSize]
        hostingView.onIntrinsicSizeChange = { [weak self] in
            // Invalidation happens during layout: resize on the next turn.
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.layout() } }
        }
        panel.contentView = hostingView
        hosting = hostingView
        panel.resetFrameAnimation()
        let placed = layout()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.slideIn(to: placed ?? panel.frame, reduceMotion: reduceMotion, makeKey: true)
        installMonitors()
        onChange?()
    }

    func close() {
        guard isShown else { return }
        removeMonitors()
        panel.orderOut(nil)
        panel.resetFrameAnimation()
        hosting = nil
        panel.contentView = nil
        model.isListOpen = false
        onChange?()
    }

    /// Fits the panel to the card and hangs it under the status item again; the top edge stays put.
    @discardableResult
    private func layout() -> CGRect? {
        guard let hosting else { return nil }
        let screens = ScreenDescriptor.current()
        let screen = screens.first { $0.frame.contains(CGPoint(x: anchor.midX, y: anchor.midY)) } ?? screens.first
        guard let screen else { return nil }
        let size = CGSize(width: TK.Size.panelWidth, height: max(hosting.fittingSize.height, 1))
        let frame = PanelGeometry.menuBarPanelFrame(anchor: anchor, visibleFrame: screen.visibleFrame, size: size)
        guard frame != panel.settledFrame else { return frame }
        panel.place(frame)
        panel.invalidateShadow()
        return frame
    }

    private func installMonitors() {
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        // Clicks in other apps and on the desktop.
        if let global = NSEvent.addGlobalMonitorForEvents(
            matching: clicks,
            handler: { [weak self] _ in
                MainActor.assumeIsolated { self?.close() }
            })
        {
            monitors.append(global)
        }
        // Clicks in the app's other windows. The card itself, the status item (it toggles) and menus are not outside.
        if let local = NSEvent.addLocalMonitorForEvents(
            matching: clicks,
            handler: { [weak self] event in
                MainActor.assumeIsolated { self?.closeForClick(in: event.window) }
                return event
            })
        {
            monitors.append(local)
        }
        // Esc, while the card is key (an open menu takes it first).
        if let keys = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown,
            handler: { [weak self] event in
                guard event.keyCode == Self.escapeKeyCode else { return event }
                // AppKit calls local monitors on the main thread.
                let handled = MainActor.assumeIsolated { () -> Bool in
                    guard let self, event.window === self.panel else { return false }
                    self.close()
                    return true
                }
                return handled ? nil : event
            })
        {
            monitors.append(keys)
        }
        deactivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    private func removeMonitors() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
        if let deactivationObserver { NotificationCenter.default.removeObserver(deactivationObserver) }
        deactivationObserver = nil
    }

    private func closeForClick(in window: NSWindow?) {
        guard let window, window !== panel, window !== anchorWindow() else { return }
        if window.level.rawValue >= NSWindow.Level.popUpMenu.rawValue { return }
        close()
    }

    private static let escapeKeyCode: UInt16 = 53
}
