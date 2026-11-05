import AppKit

struct ScreenDescriptor: Equatable, Sendable {
    let id: UInt32
    let frame: CGRect
    let visibleFrame: CGRect

    @MainActor
    static func current() -> [ScreenDescriptor] {
        NSScreen.screens.map { screen in
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            return ScreenDescriptor(
                id: number?.uint32Value ?? 0, frame: screen.frame, visibleFrame: screen.visibleFrame)
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

    /// Where a panel starts when it slides down into `final`: the same frame, shifted up.
    static func slideStartFrame(for final: CGRect, offset: CGFloat = TK.Motion.panelSlideOffset) -> CGRect {
        final.offsetBy(dx: 0, dy: offset)
    }

    /// A visible panel only animates to a frame that keeps its left edge and top edge (a pure height change under
    /// the same anchor); any other change jumps, so it never travels across the screen.
    static func resizesInPlace(from old: CGRect, to new: CGRect) -> Bool {
        abs(old.minX - new.minX) < 0.5 && abs(old.maxY - new.maxY) < 0.5
    }
}
