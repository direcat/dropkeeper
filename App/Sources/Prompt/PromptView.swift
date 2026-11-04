import DropKeeperCore
import SwiftUI

/// The new-download prompt (design manual §7.2).
struct PromptView: View {
    let file: TrackedFile
    let stackCount: Int
    let duplicateOf: String?
    @Binding var timeline: TimelineModel
    @Binding var applyToAll: Bool
    let now: Date
    /// Remaining share (0…1) of the auto-hide countdown; nil shows no bar.
    let hideProgress: Double?
    /// Whole seconds left until the prompt hides, for the caption.
    let hideSeconds: Int?
    let onDone: () -> Void
    let onKeep: () -> Void
    let onClose: () -> Void
    let onOpen: () -> Void
    let onDeleteDuplicate: () -> Void
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: TK.Space.l) {
            header
            if let duplicateOf {
                duplicateRow(of: duplicateOf)
            }
            if stackCount > 1 {
                Toggle(isOn: $applyToAll) {
                    Text("Apply to all \(stackCount) new files")
                        .font(.system(size: TK.TextSize.small))
                        .foregroundStyle(TK.Palette.textSecondary)
                }
                .toggleStyle(.checkbox)
                .focusEffectDisabled(false)
            }
            TimelineView(model: $timeline, now: now)
            Rectangle().fill(TK.Palette.hairline).frame(height: TK.Size.cardStroke)
            HStack {
                Button("Keep", action: onKeep)
                    .buttonStyle(PromptButtonStyle(primary: false))
                    .focusEffectDisabled(false)
                Spacer()
                Button(timeline.confirmLabel, action: onDone)
                    .buttonStyle(PromptButtonStyle(primary: true))
                    .keyboardShortcut(.defaultAction)
                    .focusEffectDisabled(false)
            }
            hideIndicator
        }
        .padding(TK.Space.l)
        .frame(width: TK.Size.panelWidth)
        .focusable()
        // The container only receives the arrow keys; its own ring is hidden, controls keep the system ring (§9).
        .focusEffectDisabled()
        .focused($focused)
        .defaultFocus($focused, true)
        .onAppear { focused = true }
        .onKeyPress(.leftArrow) {
            withAnimation(TimelineView.selectionAnimation(reduceMotion: reduceMotion)) { timeline.moveLeft() }
            return .handled
        }
        .onKeyPress(.rightArrow) {
            withAnimation(TimelineView.selectionAnimation(reduceMotion: reduceMotion)) { timeline.moveRight() }
            return .handled
        }
    }

    private var header: some View {
        HStack(spacing: TK.Space.m) {
            FinderIcon(path: file.path, kind: file.kind, size: TK.Size.promptIcon)
                .clipShape(RoundedRectangle(cornerRadius: TK.Radius.control))
            VStack(alignment: .leading, spacing: 2) {
                FileNameLink(
                    name: file.displayName, font: .system(size: TK.TextSize.title, weight: .semibold), action: onOpen)
                Text(Self.metadata(for: file))
                    .font(.system(size: TK.TextSize.small))
                    .foregroundStyle(TK.Palette.textSecondary)
            }
            Spacer(minLength: TK.Space.s)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: TK.TextSize.caption, weight: .semibold))
                    .frame(width: TK.Size.closeButton, height: TK.Size.closeButton)
                    .background(TK.Palette.fill, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .focusEffectDisabled(false)
            .foregroundStyle(TK.Palette.textSecondary)
            .accessibilityLabel(Text("Close"))
        }
    }

    private func duplicateRow(of name: String) -> some View {
        HStack(spacing: TK.Space.m) {
            Text("Same as \(name)")
                .font(.system(size: TK.TextSize.small))
                .foregroundStyle(TK.Palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: TK.Space.s)
            Button(action: onDeleteDuplicate) {
                Text("Delete duplicate")
                    .padding(.horizontal, TK.Space.s)
                    .padding(.vertical, TK.Space.xs)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // Mouse-only, like the notice bars: keyboard focus and Return stay with the prompt.
            .focusable(false)
            .font(.system(size: TK.TextSize.small, weight: .medium))
            .foregroundStyle(TK.Palette.accentText)
            // Keep the visible text aligned with the panel padding despite the larger hit area.
            .padding(.trailing, -TK.Space.s)
        }
    }

    /// "49 KB · Downloads": the size and the name of the folder the file lies in.
    static func metadata(for file: TrackedFile) -> String {
        let size = file.sizeBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
        let folder = URL(fileURLWithPath: file.path).deletingLastPathComponent().lastPathComponent
        return [size, folder.isEmpty ? nil : folder].compactMap(\.self).joined(separator: " · ")
    }

    static func hideCaption(seconds: Int?) -> String? {
        seconds.map { String(localized: "Hides in \($0) s · stays in the list") }
    }

    @ViewBuilder
    private var hideIndicator: some View {
        if let hideProgress, let caption = Self.hideCaption(seconds: hideSeconds) {
            VStack(spacing: TK.Space.s) {
                Capsule().fill(TK.Palette.fill)
                    .frame(height: TK.Size.hideBar)
                    .overlay(alignment: .leading) {
                        GeometryReader { geometry in
                            Capsule().fill(TK.Palette.textTertiary)
                                .frame(width: geometry.size.width * min(max(hideProgress, 0), 1))
                        }
                    }
                Text(caption)
                    .font(.system(size: TK.TextSize.caption))
                    .foregroundStyle(TK.Palette.textTertiary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(caption))
        }
    }
}

/// A file name that opens the file in its default app; it underlines on hover like a link.
struct FileNameLink: View {
    let name: String
    let font: Font
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(name)
                .font(font)
                .underline(hovering)
                .foregroundStyle(hovering ? TK.Palette.accentText : TK.Palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .buttonStyle(.plain)
        // Mouse-only: keyboard focus and Return stay with the prompt's default action (VoiceOver can still open it).
        .focusable(false)
        .pointerStyle(.link)
        .onHover { hovering = $0 }
        .accessibilityLabel(Text("Open \(name)"))
    }
}

struct PromptButtonStyle: ButtonStyle {
    let primary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: TK.TextSize.title, weight: .medium))
            .padding(.horizontal, TK.Space.m)
            .padding(.vertical, TK.Space.s)
            .foregroundStyle(primary ? TK.Palette.onAccent : TK.Palette.textPrimary)
            .background(
                primary ? TK.Palette.accent : TK.Palette.fill,
                in: RoundedRectangle(cornerRadius: TK.Radius.control)
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

#Preview {
    @Previewable @State var timeline = TimelineModel(
        durations: Settings().timelineStops, preselect: .expireAfter(3600))
    @Previewable @State var applyToAll = false
    let now = Date()
    let file = TrackedFile(
        id: "preview", folderId: 1, path: "/tmp/Quarterly report final v2.pdf", inode: 1, volumeId: "V",
        displayName: "Quarterly report final v2.pdf", kind: .document, sizeBytes: 2_400_000, state: .pending,
        firstSeen: now, expiresAt: nil, trashPath: nil, failureCount: 0, updatedAt: now)
    PromptView(
        file: file, stackCount: 3, duplicateOf: "Quarterly report final.pdf", timeline: $timeline,
        applyToAll: $applyToAll, now: now, hideProgress: 0.7, hideSeconds: 21,
        onDone: {}, onKeep: {}, onClose: {}, onOpen: {}, onDeleteDuplicate: {}
    )
    .background(TK.Palette.cardTint)
}
