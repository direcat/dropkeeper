import AppKit
import SwiftUI

/// The system popover material behind the window, so the card blurs whatever is under it.
private struct PopoverMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// A frosted card: blurred backdrop, a light or dark tint and a white inner highlight.
/// The soft shadow comes from the window.
struct GlassCard<Content: View>: View {
    let radius: CGFloat
    @ViewBuilder let content: Content

    init(radius: CGFloat = TK.Radius.card, @ViewBuilder content: () -> Content) {
        self.radius = radius
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                ZStack {
                    PopoverMaterial()
                    TK.Palette.cardTint
                }
            }
            .clipShape(shape)
            .overlay { shape.strokeBorder(TK.Palette.cardEdge, lineWidth: TK.Size.cardStroke) }
    }
}
