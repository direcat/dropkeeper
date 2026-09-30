import AppKit
import DropKeeperCore
import SwiftUI

enum OnboardingStep: Equatable {
    case needsAccess, granted, denied

    static func state(folders: [WatchedFolder], downloads: URL) -> OnboardingStep {
        guard
            let folder = folders.first(where: {
                $0.path == downloads.resolvingSymlinksInPath().path || $0.path == downloads.path
            })
        else { return .needsAccess }
        return folder.status == .ok ? .granted : .denied
    }
}

struct OnboardingView: View {
    let model: AppModel
    let downloads: URL
    let onDone: () -> Void
    @State private var launchAtLogin = true

    private static let filesAndFoldersSettings = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")!

    var body: some View {
        let step = OnboardingStep.state(folders: model.folders, downloads: downloads)
        VStack(spacing: TK.Space.xl) {
            Image("Lockup").resizable().scaledToFit().frame(height: 32)
            Image("Onboarding").resizable().scaledToFit().frame(width: 320, height: 160)
            Text(
                """
                Every new download gets an expiry. Pick 30 minutes, a day, or keep it. \
                When time is up, DropKeeper moves the file to the Trash.
                """
            )
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            Label("100 % offline — no analytics, no tracking, nothing leaves your Mac.", systemImage: "lock")
                .font(.callout)
                .foregroundStyle(.secondary)
            switch step {
            case .needsAccess:
                Button("Allow access to Downloads") { Task { await model.addFolder(downloads) } }
                    .buttonStyle(.borderedProminent)
            case .granted:
                Label("Downloads is watched", systemImage: "checkmark.circle").foregroundStyle(Color.accentColor)
            case .denied:
                VStack(spacing: TK.Space.s) {
                    Image("Permission").resizable().scaledToFit().frame(width: 64, height: 64)
                    Text(
                        """
                        DropKeeper has no access to Downloads. \
                        Allow it in System Settings → Privacy & Security → Files and Folders.
                        """
                    )
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Open System Settings") {
                            NSWorkspace.shared.open(Self.filesAndFoldersSettings)
                        }
                        Button("Check again") { Task { await model.refreshFolders() } }
                    }
                }
            }
            Toggle("Launch at login", isOn: $launchAtLogin)
            Button("Done") {
                Task {
                    var settings = model.settings
                    settings.launchAtLogin = launchAtLogin
                    await model.update(settings)
                    model.completeOnboarding()
                    onDone()
                }
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(TK.Space.xl)
        .frame(width: 480)
        .onAppear { launchAtLogin = model.settings.launchAtLogin }
    }
}
