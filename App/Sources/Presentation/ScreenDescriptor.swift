import AppKit
import DropKeeperCore

struct ScreenDescriptor: Equatable, Sendable {
    let id: UInt32
    let frame: CGRect
    let visibleFrame: CGRect
    let isBuiltIn: Bool
    /// The first screen: it holds the menu bar.
    let isPrimary: Bool
    /// Hardware notch in global screen coordinates, nil without a notch.
    let notchRect: CGRect?
    /// The mouse pointer is on this screen right now.
    let containsPointer: Bool

    @MainActor
    static func current() -> [ScreenDescriptor] {
        let pointer = NSEvent.mouseLocation
        let rightmostEdge = NSScreen.screens.map(\.frame.maxX).max()
        return NSScreen.screens.enumerated().map { index, screen in
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            let id = number?.uint32Value ?? 0
            let notch = NotchGeometry.notchRect(
                screenFrame: screen.frame,
                leftWidth: screen.auxiliaryTopLeftArea?.width ?? 0,
                rightWidth: screen.auxiliaryTopRightArea?.width ?? 0,
                topInset: screen.safeAreaInsets.top)
            return ScreenDescriptor(
                id: id, frame: screen.frame, visibleFrame: screen.visibleFrame,
                isBuiltIn: number != nil && CGDisplayIsBuiltin(id) != 0,
                isPrimary: index == 0, notchRect: notch,
                containsPointer: NotchGeometry.contains(
                    pointer, frame: screen.frame, isRightmost: screen.frame.maxX == rightmostEdge))
        }
    }
}

enum PresentationTarget: Equatable {
    case notch(ScreenDescriptor)
    case menuBar
}

enum PresentationResolver {
    /// Where a prompt, notice or error opens. Automatic follows the pointer: the notch when the pointer is on a
    /// notched built-in display, else the menu bar panel.
    static func resolve(_ setting: PromptPresentation, screens: [ScreenDescriptor]) -> PresentationTarget {
        let notched = notchedScreens(screens)
        switch setting {
        case .menuBar:
            return .menuBar
        case .automatic:
            return notched.first(where: \.containsPointer).map(PresentationTarget.notch) ?? .menuBar
        case .notch:
            return notched.first.map(PresentationTarget.notch) ?? .menuBar
        }
    }

    /// Where the closed notch and its hover list live: on any connected notched display, independent of the
    /// pointer, so the list is always one hover away. Never with the menu bar setting.
    static func idleTarget(_ setting: PromptPresentation, screens: [ScreenDescriptor]) -> PresentationTarget {
        switch setting {
        case .menuBar:
            return .menuBar
        case .automatic, .notch:
            return notchedScreens(screens).first.map(PresentationTarget.notch) ?? .menuBar
        }
    }

    static func notchedScreens(_ screens: [ScreenDescriptor]) -> [ScreenDescriptor] {
        screens.filter { $0.isBuiltIn && $0.notchRect != nil }
    }
}

enum NotchGeometry {
    /// Pointer hit test in global AppKit coordinates. The left edge belongs to the screen (the right edge to its
    /// neighbor), except on the rightmost display, which has no neighbor; vertically both edges count, because the
    /// pointer on the top row reports `maxY`.
    static func contains(_ point: CGPoint, frame: CGRect, isRightmost: Bool = false) -> Bool {
        let insideX = point.x >= frame.minX && (isRightmost ? point.x <= frame.maxX : point.x < frame.maxX)
        return insideX && point.y >= frame.minY && point.y <= frame.maxY
    }

    /// Width of the black area either side of the notch in the closed state.
    static let sideWidth: CGFloat = 56

    /// Derived from widths and the safe-area inset only, so it is independent of the coordinate space of the
    /// auxiliary areas.
    static func notchRect(screenFrame: CGRect, leftWidth: CGFloat, rightWidth: CGFloat, topInset: CGFloat) -> CGRect? {
        guard topInset > 0, leftWidth > 0, rightWidth > 0, leftWidth + rightWidth < screenFrame.width else {
            return nil
        }
        return CGRect(
            x: screenFrame.minX + leftWidth, y: screenFrame.maxY - topInset,
            width: screenFrame.width - leftWidth - rightWidth, height: topInset)
    }

    /// Open panel: hangs from the top edge, centered on the notch, kept inside the screen.
    static func panelFrame(notch: CGRect, screenFrame: CGRect, size: CGSize) -> CGRect {
        let originX = min(max(notch.midX - size.width / 2, screenFrame.minX), screenFrame.maxX - size.width)
        return CGRect(x: originX, y: screenFrame.maxY - size.height, width: size.width, height: size.height)
    }

    /// Closed state: the notch widened by `sideWidth` on both sides.
    static func idleFrame(notch: CGRect) -> CGRect {
        notch.insetBy(dx: -sideWidth, dy: 0)
    }

    /// Menu bar panel: just under the status item, 8 pt away from the screen edges.
    static func menuBarPanelFrame(anchor: CGRect, visibleFrame: CGRect, size: CGSize) -> CGRect {
        let margin: CGFloat = 8
        let originX = min(
            max(anchor.midX - size.width / 2, visibleFrame.minX + margin), visibleFrame.maxX - size.width - margin)
        let top = min(anchor.minY, visibleFrame.maxY) - 6
        return CGRect(x: originX, y: top - size.height, width: size.width, height: size.height)
    }
}
