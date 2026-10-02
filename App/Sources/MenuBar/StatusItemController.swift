import AppKit
import SwiftUI

enum StatusIcon: Equatable {
    case idle, attention, warning

    var imageName: String {
        switch self {
        case .idle: "MenuBarIdle"
        case .attention: "MenuBarAttention"
        case .warning: "MenuBarWarning"
        }
    }

    static func state(hasProblems: Bool, quietMode: Bool, hasPending: Bool) -> StatusIcon {
        if hasProblems { return .warning }
        if quietMode && hasPending { return .attention }
        return .idle
    }
}

enum StatusTitle: Equatable {
    case none
    case count(Int)
    case countdown(Int)

    static func make(scheduledCount: Int, urgentSeconds: Int?) -> StatusTitle {
        if let urgentSeconds { return .countdown(urgentSeconds) }
        return scheduledCount > 0 ? .count(scheduledCount) : .none
    }
}

enum StatusAccessibility {
    /// VoiceOver value of the status item: the count, or the countdown during the last seconds.
    static func value(scheduledCount: Int, urgentSeconds: Int?) -> String {
        if let urgentSeconds { return String(localized: "Deleting in \(TimeLabels.countdown(urgentSeconds))") }
        if scheduledCount == 0 { return String(localized: "No files scheduled") }
        return String(localized: "\(scheduledCount) files scheduled")
    }
}

enum StatusPulse {
    static let dimmedAlpha: CGFloat = 0.3

    /// The countdown dot alternates between full and dimmed on each second tick; Reduce Motion keeps it solid.
    static func dotAlpha(now: Date, reduceMotion: Bool) -> CGFloat {
        if reduceMotion { return 1 }
        return Int(now.timeIntervalSince1970).isMultiple(of: 2) ? 1 : dimmedAlpha
    }
}

/// The menu bar anchor: icon, count or countdown, and a popover with the pending list.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let model: AppModel
    private let actions: AppActions
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    /// Called after the popover opened or closed, so the floating panel can stop or start showing errors.
    var onPopoverChange: (@MainActor () -> Void)?

    init(model: AppModel, actions: AppActions) {
        self.model = model
        self.actions = actions
        super.init()
        popover.behavior = .transient
        popover.delegate = self
        popover.animates = true
        popover.appearance = NSAppearance(named: .darkAqua)
        let hosting = NSHostingController(rootView: PendingListView(model: model, actions: actions))
        // Without this the popover is laid out at NSPopover's default 320×320 and then shrinks,
        // leaving it hanging far below the menu bar icon.
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        if let button = item.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.imagePosition = .imageLeading
            button.setAccessibilityLabel(String(localized: "DropKeeper"))
        }
        ObservationLoop.run({ [weak self] in self?.readState() }, onChange: { [weak self] in self?.update() })
        update()
    }

    var anchorFrame: CGRect? { item.button?.window?.frame }
    var isPopoverShown: Bool { popover.isShown }

    /// Closes the pending list before another window (Settings, the prompt) takes over.
    func closePopover() {
        if popover.isShown { popover.performClose(nil) }
    }

    private func readState() {
        _ = model.hasProblems
        _ = model.settings.quietMode
        _ = model.pending.count
        _ = model.scheduled.count
        _ = model.urgentSeconds
        _ = model.now
    }

    private func update() {
        guard let button = item.button else { return }
        let icon = StatusIcon.state(
            hasProblems: model.hasProblems, quietMode: model.settings.quietMode, hasPending: !model.pending.isEmpty)
        let image = NSImage(named: icon.imageName)
        image?.isTemplate = true
        button.image = image
        button.setAccessibilityValue(
            StatusAccessibility.value(scheduledCount: model.scheduled.count, urgentSeconds: model.urgentSeconds))
        switch StatusTitle.make(scheduledCount: model.scheduled.count, urgentSeconds: model.urgentSeconds) {
        case .none:
            button.attributedTitle = NSAttributedString(string: "")
        case .count(let count):
            button.attributedTitle = NSAttributedString(
                string: " \(count)",
                attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .bold).rounded()])
        case .countdown(let seconds):
            let urgent = NSColor(TK.Notch.urgent)
            let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
            let alpha = StatusPulse.dotAlpha(
                now: model.now, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
            let title = NSMutableAttributedString(
                string: " ●",
                attributes: [.font: font, .foregroundColor: urgent.withAlphaComponent(alpha)])
            title.append(
                NSAttributedString(
                    string: " \(TimeLabels.countdown(seconds))",
                    attributes: [.font: font, .foregroundColor: urgent]))
            button.attributedTitle = title
        }
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = item.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            // Activating the app makes ⌘, and ⌘Q from the main menu work inside the popover.
            NSApp.activate()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            onPopoverChange?()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        onPopoverChange?()
    }
}

extension NSFont {
    fileprivate func rounded() -> NSFont {
        guard let descriptor = fontDescriptor.withDesign(.rounded) else { return self }
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }
}
