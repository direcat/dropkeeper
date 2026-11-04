import AppKit

struct ScreenDescriptor: Equatable, Sendable {
    let id: UInt32
    let frame: CGRect
    let visibleFrame: CGRect
    let isBuiltIn: Bool
    /// The first screen: it holds the menu bar.
    let isPrimary: Bool

    @MainActor
    static func current() -> [ScreenDescriptor] {
        NSScreen.screens.enumerated().map { index, screen in
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            let id = number?.uint32Value ?? 0
            return ScreenDescriptor(
                id: id, frame: screen.frame, visibleFrame: screen.visibleFrame,
                isBuiltIn: number != nil && CGDisplayIsBuiltin(id) != 0, isPrimary: index == 0)
        }
    }
}

enum PanelGeometry {
    /// Menu bar panel: just under the status item, 8 pt away from the screen edges.
    static func menuBarPanelFrame(anchor: CGRect, visibleFrame: CGRect, size: CGSize) -> CGRect {
        let margin: CGFloat = 8
        let originX = min(
            max(anchor.midX - size.width / 2, visibleFrame.minX + margin), visibleFrame.maxX - size.width - margin)
        let top = min(anchor.minY, visibleFrame.maxY) - 6
        return CGRect(x: originX, y: top - size.height, width: size.width, height: size.height)
    }
}
