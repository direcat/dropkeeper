import DropKeeperCore
import SwiftUI

/// The new-download prompt (design manual §7.2).
struct PromptView: View {
    let file: TrackedFile
    let stackCount: Int
    @Binding var timeline: TimelineModel
    @Binding var applyToAll: Bool
    let now: Date
    let onDone: () -> Void
    let onKeep: () -> Void
    let onClose: () -> Void
    let onOpen: () -> Void
    @State private var nameHovering = false
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: TK.Space.l) {
            header
            if stackCount > 1 {
                Toggle(isOn: $applyToAll) {
                    Text("Apply to all \(stackCount) new files")
                        .font(.system(size: TK.TextSize.small))
                        .foregroundStyle(TK.Notch.textSecondary)
                }
                .toggleStyle(.checkbox)
                .focusEffectDisabled(false)
            }
            TimelineView(model: $timeline, now: now)
            HStack {
                Button("Ignore", action: onKeep)
                    .buttonStyle(PromptButtonStyle(primary: false))
                    .focusEffectDisabled(false)
                Spacer()
                Button(timeline.confirmLabel, action: onDone)
                    .buttonStyle(PromptButtonStyle(primary: true))
                    .keyboardShortcut(.defaultAction)
                    .focusEffectDisabled(false)
            }
        }
        .padding(TK.Space.l)
        .frame(width: TK.Size.notchPanelWidth)
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
            FileGlyph(kind: file.kind)
            VStack(alignment: .leading, spacing: 2) {
                fileName
                Text(metadata)
                    .font(.system(size: TK.TextSize.small))
                    .foregroundStyle(TK.Notch.textSecondary)
            }
            Spacer(minLength: TK.Space.s)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: TK.TextSize.small, weight: .regular))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .focusEffectDisabled(false)
            .foregroundStyle(TK.Notch.textSecondary)
            .accessibilityLabel(Text("Close"))
        }
    }

    /// The name opens the file in its default app; it underlines on hover like a link.
    private var fileName: some View {
        Button(action: onOpen) {
            Text(file.displayName)
                .font(.system(size: TK.TextSize.title, weight: .semibold))
                .underline(nameHovering)
                .foregroundStyle(nameHovering ? TK.Notch.accentText : TK.Notch.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled(false)
        .pointerStyle(.link)
        .onHover { nameHovering = $0 }
        .accessibilityLabel(Text("Open \(file.displayName)"))
    }

    private var metadata: String {
        let size = file.sizeBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
        let stack = stackCount > 1 ? String(localized: "\(stackCount) new files") : nil
        return [size, stack].compactMap(\.self).joined(separator: " · ")
    }
}

struct PromptButtonStyle: ButtonStyle {
    let primary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: TK.TextSize.title, weight: .medium))
            .padding(.horizontal, TK.Space.m)
            .padding(.vertical, 6)
            .foregroundStyle(primary ? TK.Notch.onAccent : TK.Notch.textPrimary)
            .background(
                primary ? TK.Notch.accentFill : TK.Notch.surfaceRaised,
                in: RoundedRectangle(cornerRadius: TK.Radius.control)
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

#Preview {
    @Previewable @State var timeline = TimelineModel(
        durations: Settings().timelineStops, defaultChoice: .expireAfter(3600))
    @Previewable @State var applyToAll = false
    let now = Date()
    let file = TrackedFile(
        id: "preview", folderId: 1, path: "/tmp/Quarterly report final v2.pdf", inode: 1, volumeId: "V",
        displayName: "Quarterly report final v2.pdf", kind: .document, sizeBytes: 2_400_000, state: .pending,
        firstSeen: now, expiresAt: nil, trashPath: nil, failureCount: 0, updatedAt: now)
    PromptView(
        file: file, stackCount: 3, timeline: $timeline, applyToAll: $applyToAll, now: now,
        onDone: {}, onKeep: {}, onClose: {}, onOpen: {}
    )
    .background(TK.Notch.surface)
}
