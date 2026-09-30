import AppKit
import SwiftUI
import Testing

@testable import DropKeeper

@MainActor
@Test func panelRootRendersEveryContent() {
    let suiteName = "PanelRootViewTests"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let model = AppModel(defaults: defaults, applyLoginItem: { _ in })
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
@Test func notchInsetIsPartOfThePanelSize() {
    let suiteName = "PanelRootViewInsetTests"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let model = AppModel(defaults: defaults, applyLoginItem: { _ in })
    var file = scheduledFile(expiresIn: 0, id: "Quarterly report.pdf")
    file.state = .pending
    model.apply([file])
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
