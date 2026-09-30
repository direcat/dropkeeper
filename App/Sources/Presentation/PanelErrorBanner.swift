import SwiftUI

/// A failed prompt, list or notice action (see `PanelError`). Above the prompt, notice or list, or on its own.
struct PanelErrorBanner: View {
    let message: String
    /// On its own in the panel it also needs the bottom padding.
    var standalone = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: TK.Space.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .accessibilityHidden(true)
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.system(size: 12))
        .foregroundStyle(TK.Notch.textPrimary)
        .padding(.horizontal, TK.Space.m)
        .padding(.vertical, TK.Space.s)
        .background(TK.Notch.surfaceRaised, in: RoundedRectangle(cornerRadius: TK.Radius.control))
        .padding([.horizontal, .top], TK.Space.l)
        .padding(.bottom, standalone ? TK.Space.l : 0)
        .frame(width: TK.Size.notchPanelWidth)
        .accessibilityElement(children: .combine)
        .onAppear { AccessibilityNotification.Announcement(message).post() }
    }
}
