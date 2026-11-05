import AppKit
import DropKeeperCore
import SwiftUI

enum StopPresets {
    static let all: [TimeInterval] = [
        300, 900, 1800, 3600, 10_800, 21_600, 43_200, 86_400, 172_800, 259_200, 604_800, 864_000, 1_209_600,
        2_592_000, 7_776_000,
    ]

    static func next(after stops: [TimeInterval]) -> TimeInterval? {
        all.first { $0 > (stops.max() ?? 0) }
    }

    /// The stop "Add stop" appends: the smallest preset after the last stop, else the largest unused one below it.
    static func stopToAdd(to stops: [TimeInterval]) -> TimeInterval? {
        next(after: stops) ?? all.last { !stops.contains($0) }
    }

    /// Presets a stop's picker offers: its own value plus every preset no other stop uses, so picking one never
    /// creates a duplicate that normalization would silently drop.
    static func options(for index: Int, in stops: [TimeInterval]) -> [TimeInterval] {
        let others = stops.enumerated().filter { $0.offset != index }.map(\.element)
        return all.filter { !others.contains($0) }
    }
}

enum DefaultChoiceTag {
    static func tag(for choice: DefaultChoice, stops: [TimeInterval]) -> Int {
        if case .lastChosen = choice { return -2 }
        guard case .expireAfter(let duration) = choice, let index = stops.firstIndex(of: duration) else { return -1 }
        return index
    }

    static func choice(for tag: Int, stops: [TimeInterval]) -> DefaultChoice {
        if tag == -2 { return .lastChosen }
        return stops.indices.contains(tag) ? .expireAfter(stops[tag]) : .keep
    }
}

/// One Settings tab's content: a scrolling page of groups. Every tab is hosted by `SettingsRootView` under the tab
/// bar, all editing one shared `SettingsDraft`.
struct SettingsTabView: View {
    let tab: SettingsTab
    let model: AppModel
    let store: SettingsDraft

    var body: some View {
        Group {
            switch tab {
            case .general: GeneralTab(store: store)
            case .folders: FoldersTab(model: model)
            case .expiry: ExpiryTab(store: store)
            case .rules: RulesTab(store: store, model: model)
            case .data: DataTab(store: store, model: model)
            case .about: AboutTab()
            }
        }
        .font(.system(size: TK.TextSize.formBody))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { store.sync() }
        .onChange(of: model.settings) { _, _ in store.sync() }
        .alert(
            "DropKeeper",
            isPresented: Binding(
                get: { model.lastError != nil && store.activeTab == tab }, set: { if !$0 { model.clearError() } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.lastError ?? "")
        }
    }
}

/// The window's content: tabs stretched across the full width on the glass surface, and the selected tab's page.
struct SettingsRootView: View {
    let model: AppModel
    let store: SettingsDraft
    let onSelect: (SettingsTab) -> Void

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Rectangle().fill(TK.Palette.hairline).frame(height: TK.Size.separator)
            SettingsTabView(tab: store.activeTab, model: model, store: store)
                .id(store.activeTab)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { GlassSurface().ignoresSafeArea() }
    }

    private var tabBar: some View {
        HStack(spacing: TK.Space.xs) {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                tabButton(tab)
            }
        }
        .padding(.horizontal, TK.Space.m)
        .padding(.top, TK.Space.xs)
        .padding(.bottom, TK.Space.m - TK.Space.xs / 2)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isTabBar)
        .accessibilityLabel(Text("Settings tabs"))
    }

    private func tabButton(_ tab: SettingsTab) -> some View {
        let selected = store.activeTab == tab
        return Button {
            onSelect(tab)
        } label: {
            VStack(spacing: TK.Space.xs / 2) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: TK.Size.tabIcon))
                    .frame(height: TK.Size.tabIcon + TK.Space.xs)
                Text(verbatim: tab.title)
                    .font(.system(size: TK.TextSize.tabLabel))
            }
            .foregroundStyle(selected ? TK.Palette.accentText : TK.Palette.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, TK.Size.tabInset)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: TK.Radius.tab, style: .continuous).fill(TK.Palette.fill)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: tab.title))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The scrolling page of groups every tab is made of.
private struct TabPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TK.Space.l) {
                content
            }
            .padding(.horizontal, TK.Size.settingsContentSide)
            .padding(.vertical, TK.Size.settingsContentTop)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct GeneralTab: View {
    @Bindable var store: SettingsDraft
    @State private var language = AppLanguage.shared.selection

    var body: some View {
        TabPage {
            SettingsGroup("General") {
                SettingsToggleRow("Launch at login", isOn: $store.draft.launchAtLogin)
                SettingsRow("Appearance") {
                    SettingsSegmented(
                        label: "Appearance", values: Appearance.allCases, selection: $store.draft.appearance,
                        title: AppearanceLabel.title)
                }
                languagePicker
                if AppLanguage.shared.needsRestart { restartRow }
                SettingsToggleRow(
                    "Quiet mode",
                    caption: "Don't open the prompt by itself. A dot on the menu bar icon shows waiting files.",
                    isOn: $store.draft.quietMode)
                SettingsToggleRow(
                    "Apply the default action automatically",
                    caption: "New files get the default action right away instead of waiting for you.",
                    isOn: $store.draft.autoApplyDefault
                )
                .padding(.leading, TK.Space.xl)
                .disabled(!store.autoApplyAvailable)
            }
            SettingsGroup("Notifications") {
                StepSlider(
                    "Hide notifications after",
                    caption: """
                        The new-file prompt and the reminder before deletion hide by themselves. \
                        The file keeps waiting, its default action or deletion still happens on time, \
                        and it stays in the menu bar list.
                        """,
                    values: Settings.notificationTimeoutOptions, selection: $store.draft.notificationTimeout,
                    label: { DurationLabel.notificationTimeout($0) })
            }
        }
    }

    /// Names are endonyms, so a language is findable whatever the current one is.
    private static let languageNames = [
        "en": "English", "cs": "Čeština", "de": "Deutsch", "es": "Español", "fr": "Français",
    ]

    private var languagePicker: some View {
        SettingsRow("Language") {
            Picker(
                "Language",
                selection: Binding(
                    get: { language },
                    set: {
                        language = $0
                        AppLanguage.shared.select($0)
                    })
            ) {
                Text("System").tag(String?.none)
                ForEach(AppLanguage.supported, id: \.self) { code in
                    Text(verbatim: Self.languageNames[code] ?? code).tag(Optional(code))
                }
            }
            .labelsHidden()
            .frame(width: TK.Size.settingsPicker)
        }
    }

    private var restartRow: some View {
        SettingsRow("DropKeeper needs to restart to change the language.") {
            Button("Restart DropKeeper") {
                AppDelegate.relaunchOnQuit = true
                NSApp.terminate(nil)
            }
        }
    }
}

private struct FoldersTab: View {
    let model: AppModel

    var body: some View {
        TabPage {
            SettingsGroup("Watch folders") {
                ForEach(model.folders) { folder in
                    row(folder)
                }
                SettingsButtonRow("Add folder") { addFolder() }
            }
        }
    }

    private func row(_ folder: WatchedFolder) -> some View {
        SettingsRow {
            HStack(spacing: TK.Space.m) {
                Image(systemName: folder.status == .ok ? "folder" : "exclamationmark.triangle")
                    .foregroundStyle(folder.status == .ok ? TK.Palette.textSecondary : TK.Palette.warning)
                VStack(alignment: .leading) {
                    Text(verbatim: (folder.path as NSString).abbreviatingWithTildeInPath)
                    if folder.status == .noAccess {
                        Text("DropKeeper has no access to this folder.").settingsCaption()
                    } else if folder.status == .unavailable {
                        Text("This folder is not available.").settingsCaption()
                    }
                }
            }
        } control: {
            HStack {
                if folder.status == .noAccess {
                    Button("Grant access") { openPrivacySettings() }
                    Button("Check again") { Task { await model.refreshFolders() } }
                }
                Button {
                    if let id = folder.id { Task { await model.removeFolder(id: id) } }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help(Text("Remove folder"))
                .accessibilityLabel(Text("Remove folder"))
            }
        }
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Watch folder")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await model.addFolder(url) }
    }

    private func openPrivacySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")!
        NSWorkspace.shared.open(url)
    }
}

private struct ExpiryTab: View {
    @Bindable var store: SettingsDraft

    var body: some View {
        TabPage {
            timeline
            expiry
        }
        .alert("Delete files permanently?", isPresented: $store.confirmPermanent) {
            Button("Delete permanently", role: .destructive) { store.draft.deleteMode = .permanent }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Expired files will be deleted right away instead of going to the Trash. This can't be undone.")
        }
    }

    private var timeline: some View {
        SettingsGroup("Timeline", footer: Text("Times you can pick in the prompt.")) {
            ForEach(store.draft.timelineStops.indices, id: \.self) { index in
                SettingsRow {
                    Text(verbatim: "#\(index + 1)")
                } control: {
                    HStack {
                        Picker(selection: stopBinding(index)) {
                            ForEach(StopPresets.options(for: index, in: store.draft.timelineStops), id: \.self) {
                                Text(DurationLabel.short($0)).tag($0)
                            }
                        } label: {
                            Text(verbatim: "#\(index + 1)")
                        }
                        .labelsHidden()
                        .frame(width: TK.Size.settingsPicker)
                        Button {
                            store.draft.timelineStops.remove(at: index)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .disabled(store.draft.timelineStops.count <= 2)
                        .help(Text("Remove time"))
                        .accessibilityLabel(Text("Remove time"))
                    }
                }
            }
            SettingsButtonRow("Add time") {
                if let stop = StopPresets.stopToAdd(to: store.draft.timelineStops) {
                    store.draft.timelineStops.append(stop)
                }
            }
            .disabled(
                store.draft.timelineStops.count >= 5 || StopPresets.stopToAdd(to: store.draft.timelineStops) == nil)
        }
    }

    private var expiry: some View {
        SettingsGroup("Expiry") {
            SettingsRow("Default action") {
                Picker(
                    "Default action",
                    selection: Binding(
                        get: {
                            DefaultChoiceTag.tag(for: store.draft.defaultChoice, stops: store.draft.timelineStops)
                        },
                        set: {
                            store.draft.defaultChoice = DefaultChoiceTag.choice(
                                for: $0, stops: store.draft.timelineStops)
                        })
                ) {
                    Text("Last chosen time").tag(-2)
                    Text("Keep it").tag(-1)
                    ForEach(store.draft.timelineStops.indices, id: \.self) { index in
                        Text("Delete after \(DurationLabel.long(store.draft.timelineStops[index]))").tag(index)
                    }
                }
                .labelsHidden()
                .frame(width: TK.Size.settingsPicker)
            }
            StepSlider(
                "Apply default action after", values: Settings.gracePeriodOptions, selection: $store.draft.gracePeriod,
                label: { DurationLabel.long($0) })
            SettingsToggleRow("Remind before deleting", isOn: $store.draft.reminderEnabled)
            StepSlider(
                "Remind before", values: Settings.reminderLeadTimeOptions, selection: $store.draft.reminderLeadTime,
                label: { DurationLabel.long($0) }
            )
            .disabled(!store.draft.reminderEnabled)
            SettingsRow("Expired files") {
                Picker(
                    "Expired files",
                    selection: Binding(
                        get: { store.draft.deleteMode },
                        set: { mode in
                            if mode == .permanent {
                                store.confirmPermanent = true
                            } else {
                                store.draft.deleteMode = mode
                            }
                        })
                ) {
                    Text("Move to Trash").tag(DeleteMode.trash)
                    Text("Delete permanently").tag(DeleteMode.permanent)
                }
                .labelsHidden()
                .frame(width: TK.Size.settingsPicker)
            }
            SettingsToggleRow(
                "Mark scheduled files with the “Temporary” Finder tag", isOn: $store.draft.finderTagEnabled)
        }
    }

    /// Bounds-checked binding: removing a stop re-renders rows whose index may no longer exist. It ignores a value
    /// another stop already uses.
    private func stopBinding(_ index: Int) -> Binding<TimeInterval> {
        Binding(
            get: {
                let stops = store.draft.timelineStops
                return stops.indices.contains(index) ? stops[index] : stops[0]
            },
            set: { value in
                guard store.draft.timelineStops.indices.contains(index),
                    StopPresets.options(for: index, in: store.draft.timelineStops).contains(value)
                else { return }
                store.draft.timelineStops[index] = value
            })
    }
}

private struct RulesTab: View {
    @Bindable var store: SettingsDraft
    let model: AppModel
    @State private var editing: EditedRule?

    var body: some View {
        TabPage {
            RulesSection(store: store, model: model, editing: $editing)
            IgnoredFilesSection(store: store)
        }
        .sheet(item: $editing) { edited in
            RuleEditor(rule: edited.rule, isNew: edited.isNew, folders: model.folders) { saved in
                if let index = store.draft.rules.firstIndex(where: { $0.id == saved.id }) {
                    store.draft.rules[index] = saved
                } else {
                    store.draft.rules.append(saved)
                }
            }
        }
    }
}

private struct DataTab: View {
    @Bindable var store: SettingsDraft
    let model: AppModel

    private var clearedCaption: LocalizedStringKey? {
        store.clearedCount.map { "Removed \($0) records" }
    }

    var body: some View {
        TabPage {
            SettingsGroup("Data") {
                StepSlider(
                    "Keep history for", values: HistoryRetention.allCases, selection: $store.draft.historyRetention,
                    label: DurationLabel.retention)
                SettingsButtonRow("Clear history") { store.confirmClear = true }
                if let clearedCaption {
                    Text(clearedCaption).settingsCaption().frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            StatisticsSection(model: model, store: store)
        }
        .alert("Clear history?", isPresented: $store.confirmClear) {
            Button("Clear history", role: .destructive) {
                Task { await store.clearHistory() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Scheduled and waiting files are not affected.")
        }
    }
}

private struct AboutTab: View {
    private static let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"

    var body: some View {
        TabPage {
            SettingsGroup("About") {
                SettingsRow {
                    Image("Lockup").resizable().scaledToFit().frame(height: TK.Size.lockup)
                } control: {
                    Text("Version \(Self.version)")
                        .foregroundStyle(TK.Palette.textSecondary)
                }
                SettingsRow {
                    Text(
                        """
                        Free and open source (MIT). 100 % offline, no analytics, no tracking, \
                        nothing leaves your computer.
                        """)
                } control: {
                    EmptyView()
                }
                SettingsRow {
                    Link(
                        "direcat.github.io/dropkeeper",
                        destination: URL(string: "https://direcat.github.io/dropkeeper/")!)
                } control: {
                    EmptyView()
                }
            }
        }
    }
}
