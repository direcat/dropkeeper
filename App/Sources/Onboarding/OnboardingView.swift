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
    /// Why adding the folder failed; shown once, then gone.
    @State private var accessError: String?

    private static let filesAndFoldersSettings = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")!

    var body: some View {
        let step = OnboardingStep.state(folders: model.folders, downloads: downloads)
        VStack(spacing: TK.Space.xl) {
            Image("Lockup").resizable().scaledToFit().frame(height: TK.Size.onboardingLockup)
                .accessibilityLabel("DropKeeper")
                .accessibilityAddTraits(.isHeader)
            Image(decorative: "Onboarding").resizable().scaledToFit()
                .frame(width: TK.Size.onboardingArt.width, height: TK.Size.onboardingArt.height)
            Text(
                """
                Every new download gets an expiry. Pick 30 minutes, a day, or keep it. \
                When time is up, DropKeeper moves the file to the Trash.
                """
            )
            .foregroundStyle(TK.Palette.textPrimary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            Label("100 % offline, no analytics, no tracking, nothing leaves your computer.", systemImage: "lock")
                .font(.system(size: TK.TextSize.formCallout))
                .foregroundStyle(TK.Palette.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            SettingsGroup {
                accessRows(step)
                SettingsToggleRow("Launch at login", isOn: $launchAtLogin)
            }
            Button("Done") {
                Task {
                    var settings = model.settings
                    settings.launchAtLogin = launchAtLogin
                    await model.update(settings)
                    model.completeOnboarding()
                    onDone()
                }
            }
            .buttonStyle(PromptButtonStyle(primary: step == .granted))
            .keyboardShortcut(.defaultAction)
        }
        .padding(TK.Space.xl)
        .font(.system(size: TK.TextSize.formBody))
        .frame(width: TK.Size.onboardingWidth)
        .background { GlassSurface().ignoresSafeArea() }
        .onAppear { launchAtLogin = model.settings.launchAtLogin }
        .alert(
            "Couldn't watch Downloads",
            isPresented: Binding(get: { accessError != nil }, set: { if !$0 { accessError = nil } })
        ) {
            Button("OK") {}
        } message: {
            Text(accessError ?? "")
        }
    }

    @ViewBuilder
    private func accessRows(_ step: OnboardingStep) -> some View {
        switch step {
        case .needsAccess:
            SettingsRow(
                title: {
                    Button("Allow access to Downloads") { Task { await allowAccess() } }
                        .buttonStyle(PromptButtonStyle(primary: true))
                },
                control: { EmptyView() })
        case .granted:
            SettingsRow(
                title: {
                    Label("Downloads is watched", systemImage: "checkmark.circle")
                        .foregroundStyle(TK.Palette.accentText)
                },
                control: { EmptyView() })
        case .denied:
            SettingsRow(
                title: {
                    HStack(spacing: TK.Space.m) {
                        Image("Permission").resizable().scaledToFit()
                            .frame(width: TK.Size.onboardingPermission, height: TK.Size.onboardingPermission)
                            .accessibilityHidden(true)
                        Text(
                            """
                            DropKeeper has no access to Downloads. \
                            Allow it in System Settings → Privacy & Security → Files and Folders.
                            """
                        )
                        .fixedSize(horizontal: false, vertical: true)
                    }
                },
                control: { EmptyView() })
            SettingsButtonRow("Open System Settings") { NSWorkspace.shared.open(Self.filesAndFoldersSettings) }
            SettingsButtonRow("Check again") { Task { await model.refreshFolders() } }
        }
    }

    private func allowAccess() async {
        guard !(await model.addFolder(downloads)) else { return }
        accessError = model.lastError ?? String(localized: "Something went wrong. Please try again.")
        model.clearError()
    }
}
