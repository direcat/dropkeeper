import AppKit
import DropKeeperCore
import SwiftUI

enum PendingRows {
    /// Problems first, then files waiting for a decision, then scheduled files by expiry.
    static func ordered(pending: [TrackedFile], scheduled: [TrackedFile], failed: [TrackedFile]) -> [TrackedFile] {
        failed + pending + scheduled.sorted { ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture) }
    }
}

/// List of pending, scheduled and failed files (design manual §7.4).
struct PendingListView: View {
    let model: AppModel
    let actions: AppActions
    var showsFooter = true

    var body: some View {
        let rows = PendingRows.ordered(pending: model.pending, scheduled: model.scheduled, failed: model.failed)
        VStack(spacing: 0) {
            if let message = model.panelError.message {
                PanelErrorBanner(message: message)
                    .padding(.bottom, TK.Space.s)
            }
            if rows.isEmpty {
                Text("No files scheduled")
                    .font(.system(size: TK.TextSize.title))
                    .foregroundStyle(TK.Notch.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: TK.Size.listRow)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { file in
                            PendingRow(file: file, model: model, actions: actions)
                        }
                    }
                }
                .frame(height: min(CGFloat(rows.count), 5) * TK.Size.listRow)
            }
            if showsFooter {
                Rectangle().fill(TK.Notch.hairline).frame(height: 1)
                HStack {
                    Button("Settings") { actions.openSettings() }
                        .keyboardShortcut(",", modifiers: .command)
                    Spacer()
                    Button("Quit DropKeeper") { actions.quit() }
                        .keyboardShortcut("q", modifiers: .command)
                }
                .buttonStyle(.plain)
                .font(.system(size: TK.TextSize.title))
                .foregroundStyle(TK.Notch.textSecondary)
                // Same insets and height as the file rows above.
                .padding(.horizontal, TK.Space.m)
                .frame(height: TK.Size.listRow)
            }
        }
        .frame(width: TK.Size.notchPanelWidth)
        .background(TK.Notch.surface)
        .environment(\.colorScheme, .dark)
    }
}

private struct PendingRow: View {
    let file: TrackedFile
    let model: AppModel
    let actions: AppActions
    @State private var hovering = false

    var body: some View {
        HStack(spacing: TK.Space.m) {
            FinderIcon(path: file.path, kind: file.kind, size: 28)
            FileNameLink(name: file.displayName, font: .system(size: TK.TextSize.title)) {
                FileOpener.open(FinderReveal.target(for: file.path))
            }
            Spacer(minLength: TK.Space.s)
            status
            menu
        }
        .padding(.horizontal, TK.Space.m)
        .frame(height: TK.Size.listRow)
        .background(hovering ? TK.Notch.surfaceRaised : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { if file.state == .pending { actions.review(file.id) } }
        .contextMenu { menuItems }
    }

    @ViewBuilder
    private var status: some View {
        switch file.state {
        case .pending:
            Text("Waiting").font(.system(size: TK.TextSize.body)).foregroundStyle(TK.Notch.textSecondary)
        case .failed:
            Text("Couldn't move").font(.system(size: TK.TextSize.body)).foregroundStyle(TK.Notch.textSecondary)
        default:
            if let expiresAt = file.expiresAt {
                Text(TimeLabels.remaining(until: expiresAt, now: model.now))
                    .font(.system(size: TK.TextSize.body))
                    .monospacedDigit()
                    .foregroundStyle(
                        expiresAt.timeIntervalSince(model.now) < 600 ? TK.Notch.accentText : TK.Notch.textSecondary)
            }
        }
    }

    private var menu: some View {
        Menu {
            menuItems
        } label: {
            Image(systemName: "ellipsis").foregroundStyle(TK.Notch.textSecondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(Text("Actions"))
    }

    @ViewBuilder
    private var menuItems: some View {
        let reveal = FinderReveal.target(for: file.path)
        if file.state == .pending {
            Button("Show prompt") { actions.review(file.id) }
        }
        if file.state == .failed {
            Button("Retry") { Task { await model.retry([file.id]) } }
        }
        Button("Open") { FileOpener.open(FinderReveal.target(for: file.path)) }
            .disabled(reveal == .unavailable)
        Button("Keep") { Task { await model.keep([file.id]) } }
        Menu("Change time") {
            ForEach(model.settings.timelineStops, id: \.self) { seconds in
                Button(DurationLabel.short(seconds)) { Task { await model.schedule([file.id], duration: seconds) } }
            }
        }
        Button("Show in Finder") { FinderReveal.reveal(reveal) }
            .disabled(reveal == .unavailable)
        Divider()
        Button(role: .destructive) {
            Task { await deleteNow() }
        } label: {
            Text(model.settings.deleteMode == .trash ? "Move to Trash" : "Delete Permanently…")
        }
        .disabled(reveal == .unavailable)
    }

    /// Permanent deletion asks first; the Trash can be undone from the notice.
    private func deleteNow() async {
        if model.settings.deleteMode == .permanent, !DeleteConfirmation.confirm(name: file.displayName) { return }
        await model.deleteNow([file.id])
    }
}

/// Confirmation before a file is deleted permanently from the list.
private enum DeleteConfirmation {
    @MainActor
    static func confirm(name: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = String(localized: "Delete “\(name)” permanently?")
        alert.informativeText = String(localized: "This can't be undone.")
        alert.alertStyle = .warning
        let delete = alert.addButton(withTitle: String(localized: "Delete permanently"))
        delete.hasDestructiveAction = true
        alert.addButton(withTitle: String(localized: "Cancel"))
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }
}
