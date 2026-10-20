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

struct SettingsView: View {
    let model: AppModel
    @State private var draft = Settings()
    @State private var newExtension = ""
    @State private var confirmPermanent = false
    @State private var confirmClear = false
    @State private var clearedCount: Int?
    @State private var language = AppLanguage.shared.selection

    init(model: AppModel) {
        self.model = model
    }

    var body: some View {
        Form {
            general
            folders
            timeline
            expiry
            ignored
            data
            about
        }
        .formStyle(.grouped)
        .font(.system(size: TK.TextSize.formBody))
        .controlSize(.large)
        .frame(width: 600, height: 640)
        .onAppear { draft = model.settings }
        .onChange(of: model.settings) { _, new in draft = new }
        .onChange(of: draft) { _, new in
            guard new != model.settings else { return }
            Task { await save(new) }
        }
        .alert("Delete files permanently?", isPresented: $confirmPermanent) {
            Button("Delete permanently", role: .destructive) { draft.deleteMode = .permanent }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Expired files will be deleted right away instead of going to the Trash. This can't be undone.")
        }
        .alert("Clear history?", isPresented: $confirmClear) {
            Button("Clear history", role: .destructive) {
                Task { clearedCount = await model.clearHistory() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Scheduled and waiting files are not affected.")
        }
        .alert(
            "DropKeeper", isPresented: Binding(get: { model.lastError != nil }, set: { if !$0 { model.clearError() } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.lastError ?? "")
        }
    }

    private var general: some View {
        Section("General") {
            Toggle("Launch at login", isOn: $draft.launchAtLogin)
            Picker("Show new downloads", selection: $draft.promptPresentation) {
                Text("Under the menu bar icon").tag(PromptPresentation.menuBar)
                Text("Automatically").tag(PromptPresentation.automatic)
                Text("In the notch").tag(PromptPresentation.notch)
            }
            Text("Automatically shows new downloads in the notch when the pointer is on the laptop screen.")
                .font(.system(size: TK.TextSize.formCaption))
                .foregroundStyle(.secondary)
            languagePicker
            Toggle(isOn: $draft.quietMode) {
                Text("Quiet mode")
                Text("Don't open the prompt by itself. A dot on the menu bar icon shows waiting files.")
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

    private var folders: some View {
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

    private var timeline: some View {
        Section {
            ForEach(draft.timelineStops.indices, id: \.self) { index in
                HStack {
                    Picker(selection: stopBinding(index)) {
                        ForEach(StopPresets.options(for: index, in: draft.timelineStops), id: \.self) {
                            Text(DurationLabel.short($0)).tag($0)
                        }
                    } label: {
                        Text(verbatim: "#\(index + 1)")
                    }
                    Button {
                        draft.timelineStops.remove(at: index)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .disabled(draft.timelineStops.count <= 2)
                    .help(Text("Remove time"))
                    .accessibilityLabel(Text("Remove time"))
                }
            }
            Button("Add time") {
                if let stop = StopPresets.stopToAdd(to: draft.timelineStops) { draft.timelineStops.append(stop) }
            }
            .disabled(draft.timelineStops.count >= 5 || StopPresets.stopToAdd(to: draft.timelineStops) == nil)
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
                    get: { DefaultChoiceTag.tag(for: draft.defaultChoice, stops: draft.timelineStops) },
                    set: { draft.defaultChoice = DefaultChoiceTag.choice(for: $0, stops: draft.timelineStops) })
            ) {
                Text("Keep it").tag(-1)
                ForEach(draft.timelineStops.indices, id: \.self) { index in
                    Text("Delete after \(DurationLabel.long(draft.timelineStops[index]))").tag(index)
                }
            }
            Picker("Apply default action after", selection: $draft.gracePeriod) {
                ForEach(Settings.gracePeriodOptions, id: \.self) { Text(DurationLabel.long($0)).tag($0) }
            }
            Picker(
                "Expired files",
                selection: Binding(
                    get: { draft.deleteMode },
                    set: { mode in
                        if mode == .permanent { confirmPermanent = true } else { draft.deleteMode = mode }
                    })
            ) {
                Text("Move to Trash").tag(DeleteMode.trash)
                Text("Delete permanently").tag(DeleteMode.permanent)
            }
            Toggle("Mark scheduled files with the “Temporary” Finder tag", isOn: $draft.finderTagEnabled)
        }
    }

    private var ignored: some View {
        Section("Ignored extensions") {
            ForEach(draft.ignoredExtensions, id: \.self) { ext in
                HStack {
                    Text(verbatim: ".\(ext)")
                    Spacer()
                    Button {
                        draft.ignoredExtensions.removeAll { $0 == ext }
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
                    .disabled(Self.trimmedExtension(newExtension).isEmpty)
            }
        }
    }

    private var data: some View {
        Section("Data") {
            Picker("Keep history for", selection: $draft.historyRetention) {
                Text("1 month").tag(HistoryRetention.oneMonth)
                Text("3 months").tag(HistoryRetention.threeMonths)
                Text("6 months").tag(HistoryRetention.sixMonths)
                Text("1 year").tag(HistoryRetention.oneYear)
                Text("2 years").tag(HistoryRetention.twoYears)
                Text("Forever").tag(HistoryRetention.forever)
            }
            HStack {
                Button("Clear history now…") { confirmClear = true }
                if let clearedCount {
                    Text("Removed \(clearedCount) records").foregroundStyle(.secondary)
                }
            }
        }
    }

    private static let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"

    private var about: some View {
        Section("About") {
            HStack(alignment: .center, spacing: TK.Space.l) {
                Image("Lockup").resizable().scaledToFit().frame(height: 28)
                Spacer()
                Text("Version \(Self.version)")
                    .foregroundStyle(.secondary)
            }
            Text("Free and open source (MIT). 100 % offline, no analytics, no tracking, nothing leaves your computer.")
            Text("Inspired by TempCat.").foregroundStyle(.secondary)
            Link("github.com/direcat/dropkeeper", destination: URL(string: "https://github.com/direcat/dropkeeper")!)
        }
    }

    /// Saves an edit. The engine may normalize it (e.g. re-sort stops); when that result equals the settings it
    /// already had, `model.settings` doesn't change and `onChange` never resyncs the draft, so do it here. Setting
    /// `draft` to `model.settings` never saves again (`onChange(of: draft)` skips values equal to `model.settings`).
    private func save(_ edit: DropKeeperCore.Settings) async {
        await model.update(edit)
        if draft == edit { draft = model.settings }
    }

    /// Bounds-checked binding: removing a stop re-renders rows whose index may no longer exist. It ignores a value
    /// another stop already uses.
    private func stopBinding(_ index: Int) -> Binding<TimeInterval> {
        Binding(
            get: { draft.timelineStops.indices.contains(index) ? draft.timelineStops[index] : draft.timelineStops[0] },
            set: { value in
                guard draft.timelineStops.indices.contains(index),
                    StopPresets.options(for: index, in: draft.timelineStops).contains(value)
                else { return }
                draft.timelineStops[index] = value
            })
    }

    private static func trimmedExtension(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet(charactersIn: ". ")).lowercased()
    }

    private func addExtension() {
        let ext = Self.trimmedExtension(newExtension)
        guard !ext.isEmpty, !draft.ignoredExtensions.contains(ext) else { return }
        draft.ignoredExtensions.append(ext)
        newExtension = ""
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
