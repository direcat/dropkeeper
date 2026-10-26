import AppKit
import SwiftUI
import Testing

@testable import DropKeeper

@MainActor
@Test func panelRootRendersEveryContent() async {
    let suiteName = "PanelRootViewTests"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let model = AppModel(defaults: defaults, applyLoginItem: { _ in })
    await model.handle(.trashed([scheduledFile(expiresIn: 0, id: "a.pdf")]))  // the notice stack needs a bar
    let actions = AppActions(openSettings: {}, quit: {}, review: { _ in })
    for content in [PanelContent.notice, .idle, .idleExpanded, .hidden] {
        let view = PanelRootView(
            model: model, content: content, isNotch: true, notchWidth: 200, actions: actions,
            onHover: { _ in })
        #expect(ImageRenderer(content: view).cgImage != nil || content == .hidden)
    }
}

/// In the notch the panel hangs from the top screen edge, so its content must start below the cutout.
@MainActor
@Test func notchInsetIsPartOfThePanelSize() async {
    let suiteName = "PanelRootViewInsetTests"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let model = AppModel(defaults: defaults, applyLoginItem: { _ in })
    var file = scheduledFile(expiresIn: 0, id: "Quarterly report.pdf")
    file.state = .pending
    model.apply([file])
    await model.handle(.trashed([scheduledFile(expiresIn: 0, id: "a.pdf")]))
    let actions = AppActions(openSettings: {}, quit: {}, review: { _ in })
    for content in [PanelContent.prompt, .notice] {
        func height(inset: CGFloat) -> CGFloat {
            let view = PanelRootView(
                model: model, content: content, isNotch: true, notchWidth: 200, topInset: inset, actions: actions,
                onHover: { _ in })
            return NSHostingView(rootView: view).fittingSize.height
        }
        #expect(height(inset: 32) == height(inset: 0) + 32)
    }
}

/// A reminder above the prompt grows the panel; the prompt is still there.
@MainActor
@Test func promptWithNoticeRendersBoth() {
    let suiteName = "PanelRootViewBothTests"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let model = AppModel(defaults: defaults, applyLoginItem: { _ in })
    var pending = scheduledFile(expiresIn: 0, id: "Quarterly report.pdf")
    pending.state = .pending
    pending.expiresAt = nil
    model.apply([pending])
    let actions = AppActions(openSettings: {}, quit: {}, review: { _ in })
    func height() -> CGFloat {
        let view = PanelRootView(
            model: model, content: .prompt, isNotch: true, notchWidth: 200, actions: actions, onHover: { _ in })
        return NSHostingView(rootView: view).fittingSize.height
    }
    let promptAlone = height()
    var due = scheduledFile(expiresIn: 0, id: "Installer.dmg")
    let now = Date()
    due.updatedAt = now.addingTimeInterval(-3480)
    due.expiresAt = now.addingTimeInterval(120)
    model.apply([pending, due])
    #expect(model.reminders.due.count == 1)
    #expect(height() > promptAlone)
}
