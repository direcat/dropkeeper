import AppKit
import DropKeeperCore
import SwiftUI

enum ListSection: Equatable {
    case waiting, deletingSoon, couldNotDelete

    var title: String {
        switch self {
        case .waiting: String(localized: "Waiting for you", comment: "List section: files that need a decision")
        case .deletingSoon: String(localized: "Deleting soon", comment: "List section: scheduled files")
        case .couldNotDelete: String(localized: "Couldn't delete", comment: "List section: files that failed to move")
        }
    }
}

enum ListSections {
    /// Waiting files, then scheduled files by expiry, then the ones that could not be deleted; empty sections are
    /// left out.
    static func make(
        pending: [TrackedFile], scheduled: [TrackedFile], failed: [TrackedFile]
    ) -> [(ListSection, [TrackedFile])] {
        let soonestFirst = scheduled.sorted { ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture) }
        return [(ListSection.waiting, pending), (.deletingSoon, soonestFirst), (.couldNotDelete, failed)]
            .filter { !$0.1.isEmpty }
    }
}

/// The Upcoming tab: the sections of files, scrolling once they outgrow the card.
struct UpcomingListView: View {
    let model: AppModel
    let actions: AppActions
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        let sections = ListSections.make(pending: model.pending, scheduled: model.scheduled, failed: model.failed)
        if sections.isEmpty {
            Text("No files scheduled")
                .font(.system(size: TK.TextSize.title))
                .foregroundStyle(TK.Palette.textSecondary)
                .frame(maxWidth: .infinity, minHeight: TK.Size.fileGlyph + TK.Space.xl)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(sections, id: \.0.title) { section, files in
                        Text(section.title)
                            .font(.system(size: TK.TextSize.formCaption, weight: .semibold))
                            .foregroundStyle(TK.Palette.textSecondary)
                            .padding(.horizontal, TK.Space.xs)
                            .padding(.top, TK.Space.l)
                            .padding(.bottom, TK.Space.s)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(files) { file in
                            ListRow(file: file, section: section, model: model, actions: actions)
                        }
                    }
                }
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.height
                } action: {
                    contentHeight = $0
                }
            }
            .scrollIndicators(.hidden)
            .frame(height: min(contentHeight, TK.Size.listMaxHeight))
        }
    }
}

/// One file in the list. Every action is in the context menu and in the "•••" button that appears on hover.
private struct ListRow: View {
    let file: TrackedFile
    let section: ListSection
    let model: AppModel
    let actions: AppActions
    @State private var hovering = false
    @FocusState private var menuFocused: Bool

    var body: some View {
        HStack(spacing: TK.Space.m) {
            leading
            VStack(alignment: .leading, spacing: 1) {
                FileNameLink(name: file.displayName, font: nameFont) {
                    FileOpener.open(FinderReveal.target(for: file.path))
                }
                if let meta { Text(meta).font(.system(size: TK.TextSize.formCaption)).foregroundStyle(secondary) }
            }
            Spacer(minLength: TK.Space.s)
            trailing
            moreMenu
        }
        .padding(.horizontal, TK.Space.xs)
        .padding(.vertical, TK.Size.listRowInset)
        .background(hovering ? TK.Palette.fill : .clear, in: rowShape)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { if file.state == .pending { actions.review(file.id) } }
        .contextMenu { menuItems }
    }

    private var rowShape: RoundedRectangle { RoundedRectangle(cornerRadius: TK.Radius.control, style: .continuous) }

    private var secondary: Color { TK.Palette.textSecondary }

    private var nameFont: Font {
        .system(size: TK.TextSize.body, weight: section == .couldNotDelete ? .medium : .semibold)
    }

    /// "Downloads · 48 MB" for a waiting file, the folder alone for the others.
    private var meta: String? {
        let folder = FileLocation.folderName(of: file)
        guard section == .waiting else { return section == .couldNotDelete ? nil : folder }
        let size = file.sizeBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
        return [folder, size].compactMap(\.self).joined(separator: " · ")
    }

    @ViewBuilder
    private var leading: some View {
        switch section {
        case .waiting:
            FinderIcon(path: file.path, kind: file.kind, size: TK.Size.fileGlyph)
                .clipShape(RoundedRectangle(cornerRadius: TK.Radius.control))
        case .deletingSoon:
            ProgressRing(
                progress: RingProgress.share(for: file, now: model.now),
                tint: RingProgress.isWarning(for: file, now: model.now) ? TK.Palette.warning : TK.Palette.accent
            ) {
                FinderIcon(path: file.path, kind: file.kind, size: TK.Size.listIcon)
            }
        case .couldNotDelete:
            FinderIcon(path: file.path, kind: file.kind, size: TK.Size.listIcon)
                .frame(width: TK.Size.fileGlyph, height: TK.Size.fileGlyph)
                .opacity(0.6)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch section {
        case .waiting:
            Button("Decide") { actions.review(file.id) }
                .buttonStyle(PromptButtonStyle(primary: false))
                .accessibilityLabel(Text("Decide for \(file.displayName)"))
        case .deletingSoon:
            if let expiresAt = file.expiresAt {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(TimeLabels.remaining(until: expiresAt, now: model.now))
                        .font(.system(size: TK.TextSize.body, weight: .semibold))
                        .monospacedDigit()
                    Text(TimeLabels.absolute(at: expiresAt, now: model.now))
                        .font(.system(size: TK.TextSize.formCaption))
                        .foregroundStyle(secondary)
                }
                .accessibilityElement(children: .combine)
            }
        case .couldNotDelete:
            Button("Retry") { Task { await model.retry([file.id]) } }
                .buttonStyle(PanelTextButtonStyle(tint: TK.Palette.destructive))
                .accessibilityLabel(Text("Retry \(file.displayName)"))
        }
    }

    private var moreMenu: some View {
        Menu {
            menuItems
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: TK.TextSize.formCaption, weight: .bold))
                .frame(width: TK.Size.closeButton, height: TK.Size.closeButton)
                .background(TK.Palette.fill, in: Circle())
                .contentShape(Circle())
                .foregroundStyle(secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .focused($menuFocused)
        // Out of sight until the pointer or the keyboard is on the row, but always there for VoiceOver.
        .opacity(hovering || menuFocused ? 1 : 0)
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
            Text(model.settings.deleteMode == .trash ? "Move to Trash" : "Delete Permanently")
        }
        .disabled(reveal == .unavailable)
    }

    /// Permanent deletion asks first; the Trash can be undone from the notice.
    private func deleteNow() async {
        if model.settings.deleteMode == .permanent, !DeleteConfirmation.confirm(name: file.displayName) { return }
        await model.deleteNow([file.id])
    }
}
