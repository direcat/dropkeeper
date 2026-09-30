/// App-level actions views can trigger.
struct AppActions {
    let openSettings: @MainActor () -> Void
    let quit: @MainActor () -> Void
    /// Opens the prompt for pending files even in Quiet mode.
    let review: @MainActor () -> Void
}
