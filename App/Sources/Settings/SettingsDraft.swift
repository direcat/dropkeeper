import DropKeeperCore
import Observation

/// The edit draft every Settings tab shares: edits go through `draft`, which saves itself, and the alerts' flags.
@MainActor @Observable
final class SettingsDraft {
    @ObservationIgnored let model: AppModel
    /// The tab on screen, so only its view presents the error alert.
    var activeTab = SettingsTab.general
    var confirmPermanent = false
    var confirmClear = false
    var clearedCount: Int?

    var draft: DropKeeperCore.Settings {
        didSet {
            guard draft != model.settings else { return }
            let edit = draft
            Task { await save(edit) }
        }
    }

    init(model: AppModel) {
        self.model = model
        draft = model.settings
    }

    /// Follows `model.settings` when it changes elsewhere; assigning an equal value never saves again.
    func sync() {
        if draft != model.settings { draft = model.settings }
    }

    /// Saves an edit. The engine may normalize it (e.g. re-sort stops); when that result equals the settings it
    /// already had, `model.settings` doesn't change and the view's `onChange` never resyncs the draft, so do it here.
    /// Setting `draft` to `model.settings` never saves again (`didSet` skips values equal to `model.settings`).
    private func save(_ edit: DropKeeperCore.Settings) async {
        await model.update(edit)
        if draft == edit { draft = model.settings }
    }

    func clearHistory() async {
        clearedCount = await model.clearHistory()
    }
}
