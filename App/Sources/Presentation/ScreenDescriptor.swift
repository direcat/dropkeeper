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

    @MainActor
    static func current() -> [ScreenDescriptor] {
        NSScreen.screens.enumerated().map { index, screen in
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            let id = number?.uint32Value ?? 0
            let notch =
                screen.safeAreaInsets.top > 0
                ? NotchGeometry.notchRect(
                    screenFrame: screen.frame,
                    leftArea: screen.auxiliaryTopLeftArea.map { absolute($0, in: screen.frame) },
                    rightArea: screen.auxiliaryTopRightArea.map { absolute($0, in: screen.frame) })
                : nil
            return ScreenDescriptor(
                id: id, frame: screen.frame, visibleFrame: screen.visibleFrame, isBuiltIn: CGDisplayIsBuiltin(id) != 0,
                isPrimary: index == 0, notchRect: notch)
        }
    }

    /// Auxiliary areas may be reported relative to the screen; make them global.
    private static func absolute(_ rect: CGRect, in frame: CGRect) -> CGRect {
        frame.contains(CGPoint(x: rect.midX, y: rect.midY)) ? rect : rect.offsetBy(dx: frame.minX, dy: frame.minY)
    }
}

enum PresentationTarget: Equatable {
    case notch(ScreenDescriptor)
    case menuBar
}

enum PresentationResolver {
    static func resolve(_ setting: PromptPresentation, screens: [ScreenDescriptor]) -> PresentationTarget {
        let notched = screens.filter { $0.isBuiltIn && $0.notchRect != nil }
        switch setting {
        case .menuBar:
            return .menuBar
        case .automatic:
            return notched.first(where: \.isPrimary).map(PresentationTarget.notch) ?? .menuBar
        case .notch:
            return notched.first.map(PresentationTarget.notch) ?? .menuBar
        }
    }
}

enum NotchGeometry {
    /// Width of the black area either side of the notch in the closed state.
    static let sideWidth: CGFloat = 56

    static func notchRect(screenFrame: CGRect, leftArea: CGRect?, rightArea: CGRect?) -> CGRect? {
        guard let left = leftArea, let right = rightArea, right.minX > left.maxX else { return nil }
        let height = screenFrame.maxY - min(left.minY, right.minY)
        return CGRect(x: left.maxX, y: screenFrame.maxY - height, width: right.minX - left.maxX, height: height)
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
