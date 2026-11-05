import DropKeeperCore
import Foundation

enum FileLocation {
    /// The name of the folder a file lies in. A file directly under the root has "/" as its folder: the volume's
    /// display name stands in for it. Nil when there is no name to show.
    static func folderName(of file: TrackedFile) -> String? {
        let directory = URL(fileURLWithPath: file.path).deletingLastPathComponent()
        let name = directory.path == "/" ? FileManager.default.displayName(atPath: "/") : directory.lastPathComponent
        return name.isEmpty ? nil : name
    }
}
