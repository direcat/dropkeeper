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
        guard case .expireAfter(let duration) = choice, let index = stops.firstIndex(of: duration) else { return -1 }
        return index
    }

    static func choice(for tag: Int, stops: [TimeInterval]) -> DefaultChoice {
        stops.indices.contains(tag) ? .expireAfter(stops[tag]) : .keep
    }
}

/// One Settings tab's content. Every tab is its own `Form` hosted by `SettingsWindowController`, all editing one
/// shared `SettingsDraft`.
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
            case .rules: RulesTab(store: store)
            case .data: DataTab(store: store)
            case .about: AboutTab()
            }
        }
        .formStyle(.grouped)
        .font(.system(size: TK.TextSize.formBody))
        .controlSize(.large)
        .frame(width: TK.Size.settingsWindow.width, height: TK.Size.settingsWindow.height)
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

private struct GeneralTab: View {
    @Bindable var store: SettingsDraft
    @State private var language = AppLanguage.shared.selection

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $store.draft.launchAtLogin)
                Picker("Show new downloads", selection: $store.draft.promptPresentation) {
                    Text("Under the menu bar icon").tag(PromptPresentation.menuBar)
                    Text("Automatically").tag(PromptPresentation.automatic)
                    Text("In the notch").tag(PromptPresentation.notch)
                }
                Text("Automatically shows new downloads in the notch when the pointer is on the laptop screen.")
                    .font(.system(size: TK.TextSize.formCaption))
                    .foregroundStyle(.secondary)
                languagePicker
                Toggle(isOn: $store.draft.quietMode) {
                    Text("Quiet mode")
                    Text("Don't open the prompt by itself. A dot on the menu bar icon shows waiting files.")
                }
            }
        }
    }

    /// Names are endonyms, so a language is findable whatever the current one is.
    private static let languageNames = [
        "en": "English", "cs": "Čeština", "de": "Deutsch", "es": "Español", "fr": "Français",
    ]

    @ViewBuilder private var languagePicker: some View {
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
        if AppLanguage.shared.needsRestart {
            HStack {
                Text("DropKeeper needs to restart to change the language.")
                    .font(.system(size: TK.TextSize.formCaption))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Restart DropKeeper") {
                    AppDelegate.relaunchOnQuit = true
                    NSApp.terminate(nil)
                }
            }
        }
    }
}

private struct FoldersTab: View {
    let model: AppModel

    var body: some View {
        Form {
            Section("Watch folders") {
                ForEach(model.folders) { folder in
                    HStack {
                        Image(systemName: folder.status == .ok ? "folder" : "exclamationmark.triangle")
                            .foregroundStyle(folder.status == .ok ? Color.secondary : Color.orange)
                        VStack(alignment: .leading) {
                            Text(verbatim: (folder.path as NSString).abbreviatingWithTildeInPath)
                            if folder.status == .noAccess {
                                Text("DropKeeper has no access to this folder.")
                                    .font(.system(size: TK.TextSize.formCaption))
                                    .foregroundStyle(.secondary)
                            } else if folder.status == .unavailable {
                                Text("This folder is not available.")
                                    .font(.system(size: TK.TextSize.formCaption))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
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
                Button("Add folder…") { addFolder() }
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
        Form {
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
        Section {
            ForEach(store.draft.timelineStops.indices, id: \.self) { index in
                HStack {
                    Picker(selection: stopBinding(index)) {
                        ForEach(StopPresets.options(for: index, in: store.draft.timelineStops), id: \.self) {
                            Text(DurationLabel.short($0)).tag($0)
                        }
                    } label: {
                        Text(verbatim: "#\(index + 1)")
                    }
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
            Button("Add time") {
                if let stop = StopPresets.stopToAdd(to: store.draft.timelineStops) {
                    store.draft.timelineStops.append(stop)
                }
            }
            .disabled(
                store.draft.timelineStops.count >= 5 || StopPresets.stopToAdd(to: store.draft.timelineStops) == nil)
        } header: {
            Text("Timeline")
        } footer: {
            Text("Times you can pick in the prompt.")
                .font(.system(size: TK.TextSize.formCaption))
                .foregroundStyle(.secondary)
        }
    }

    private var expiry: some View {
        Section("Expiry") {
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
                Text("Keep it").tag(-1)
                ForEach(store.draft.timelineStops.indices, id: \.self) { index in
                    Text("Delete after \(DurationLabel.long(store.draft.timelineStops[index]))").tag(index)
                }
            }
            StepSlider(
                "Apply default action after", values: Settings.gracePeriodOptions, selection: $store.draft.gracePeriod,
                label: { DurationLabel.long($0) })
            Picker(
                "Expired files",
                selection: Binding(
                    get: { store.draft.deleteMode },
                    set: { mode in
                        if mode == .permanent { store.confirmPermanent = true } else { store.draft.deleteMode = mode }
                    })
            ) {
                Text("Move to Trash").tag(DeleteMode.trash)
                Text("Delete permanently").tag(DeleteMode.permanent)
            }
            Toggle("Mark scheduled files with the “Temporary” Finder tag", isOn: $store.draft.finderTagEnabled)
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
    @State private var newExtension = ""

    var body: some View {
        Form {
            Section("Ignored extensions") {
                ForEach(store.draft.ignoredPatterns, id: \.self) { pattern in
                    HStack {
                        Text(verbatim: pattern)
                        Spacer()
                        Button {
                            store.draft.ignoredPatterns.removeAll { $0 == pattern }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help(Text("Remove extension"))
                        .accessibilityLabel(Text("Remove extension"))
                    }
                }
                HStack {
                    TextField("Extension, e.g. dmg", text: $newExtension)
                        .onSubmit(addExtension)
                    Button("Add", action: addExtension)
                        .disabled(IgnorePattern.normalize(newExtension) == nil)
                }
            }
        }
    }

    private func addExtension() {
        guard let pattern = IgnorePattern.normalize(newExtension), !store.draft.ignoredPatterns.contains(pattern) else {
            return
        }
        store.draft.ignoredPatterns.append(pattern)
        newExtension = ""
    }
}

private struct DataTab: View {
    @Bindable var store: SettingsDraft

    private static let retentionLabels: [HistoryRetention: String] = [
        .oneMonth: String(localized: "1 month"),
        .threeMonths: String(localized: "3 months"),
        .sixMonths: String(localized: "6 months"),
        .oneYear: String(localized: "1 year"),
        .twoYears: String(localized: "2 years"),
        .forever: String(localized: "Forever"),
    ]

    var body: some View {
        Form {
            Section("Data") {
                StepSlider(
                    "Keep history for", values: HistoryRetention.allCases, selection: $store.draft.historyRetention,
                    label: { Self.retentionLabels[$0] ?? "" })
                HStack {
                    Button("Clear history now…") { store.confirmClear = true }
                    if let clearedCount = store.clearedCount {
                        Text("Removed \(clearedCount) records").foregroundStyle(.secondary)
                    }
                }
            }
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
        Form {
            Section("About") {
                HStack(alignment: .center, spacing: TK.Space.l) {
                    Image("Lockup").resizable().scaledToFit().frame(height: 28)
                    Spacer()
                    Text("Version \(Self.version)")
                        .foregroundStyle(.secondary)
                }
                Text(
                    "Free and open source (MIT). 100 % offline, no analytics, no tracking, nothing leaves your computer."
                )
                Link(
                    "direcat.github.io/dropkeeper", destination: URL(string: "https://direcat.github.io/dropkeeper/")!)
            }
        }
    }
}
