import AppKit
import SwiftUI

/// A translucent system material behind the window, so the card visibly blurs whatever is under it. HUD is
/// much more see-through than the popover material; the tint on top keeps text readable.
struct GlassMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// The glass surface on its own: the blurred backdrop with the card tint. The Settings window's background.
struct GlassSurface: View {
    var body: some View {
        ZStack {
            GlassMaterial()
            TK.Palette.cardTint
        }
    }
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
            .background { GlassSurface() }
            .clipShape(shape)
            .overlay { shape.strokeBorder(TK.Palette.cardEdge, lineWidth: TK.Size.cardStroke) }
    }
}
