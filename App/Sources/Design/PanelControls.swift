import SwiftUI

/// The round ✕ of a card: a glyph on a soft fill. Callers add the button, shortcut and label.
struct RoundCloseGlyph: View {
    var body: some View {
        Image(systemName: "xmark")
            .font(.system(size: TK.TextSize.formCaption, weight: .semibold))
            .frame(width: TK.Size.closeButton, height: TK.Size.closeButton)
            .background(TK.Palette.fill, in: Circle())
            .contentShape(Circle())
            .foregroundStyle(TK.Palette.textSecondary)
    }
}

/// A text-only action next to filled buttons (Undo, Change, Delete now): same size and padding as
/// `PromptButtonStyle`, no background.
struct PanelTextButtonStyle: ButtonStyle {
    let tint: Color
    /// Pulls the label back to the card edge; 0 for a button that has neighbours on its right.
    var trailingInset: CGFloat = 0

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: TK.TextSize.small, weight: .semibold))
            .padding(.horizontal, TK.Space.m)
            .padding(.vertical, TK.Space.s)
            // Keep the visible text aligned with the card padding despite the larger hit area.
            .padding(.trailing, trailingInset)
            .foregroundStyle(tint)
            .contentShape(RoundedRectangle(cornerRadius: TK.Radius.button))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
