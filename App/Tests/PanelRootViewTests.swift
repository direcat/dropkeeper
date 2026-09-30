import SwiftUI
import Testing

@testable import DropKeeper

@MainActor
@Test func panelRootRendersEveryContent() {
    let model = AppModel(defaults: UserDefaults(suiteName: "PanelRootViewTests")!, applyLoginItem: { _ in })
    let actions = AppActions(openSettings: {}, quit: {}, review: {})
    for content in [PanelContent.notice, .idle, .idleExpanded, .hidden] {
        let view = PanelRootView(
            model: model, content: content, isNotch: true, notchWidth: 200, actions: actions,
            onHover: { _ in })
        #expect(ImageRenderer(content: view).cgImage != nil || content == .hidden)
    }
}
