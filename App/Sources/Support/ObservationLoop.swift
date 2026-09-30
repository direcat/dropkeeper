import Observation

enum ObservationLoop {
    /// Calls `onChange` every time a property read inside `read` changes, for as long as the process runs.
    @MainActor
    static func run(_ read: @escaping @MainActor () -> Void, onChange: @escaping @MainActor () -> Void) {
        withObservationTracking(read) {
            Task { @MainActor in
                onChange()
                run(read, onChange: onChange)
            }
        }
    }
}
