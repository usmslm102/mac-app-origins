import SwiftUI

struct UpdatesSettingsView: View {
    @EnvironmentObject private var updateChecker: AppUpdateChecker

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 10) {
                        statusIndicator
                            .frame(width: 20, height: 20)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(statusTitle)
                                .font(.headline)
                            Text(installedVersionLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)
                    }

                    Text(statusDetail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)

                    if let release = updateChecker.availableRelease {
                        HStack {
                            Text("Version \(release.version.description)")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Spacer(minLength: 8)

                            Button("View Release") {
                                updateChecker.openReleasePage()
                            }

                            if release.downloadURL != nil {
                                Button("Download DMG") {
                                    updateChecker.openDownload()
                                }
                                .help("Open the DMG download in your browser, then install the update manually.")
                            }
                        }
                    } else if showsBrowseReleases {
                        Link("Browse Releases on GitHub", destination: AppUpdateChecker.releasesURL)
                    }
                }
                .padding(.vertical, 2)

                Button {
                    Task {
                        await updateChecker.checkForUpdates()
                    }
                } label: {
                    Label("Check for Updates", systemImage: "arrow.clockwise")
                }
                .disabled(updateChecker.isChecking)
            } header: {
                Text("AppOrigins Updates")
            } footer: {
                if let lastCheckedAt = updateChecker.lastCheckedAt {
                    Text("Last successful check: \(lastCheckedAt.formatted(date: .abbreviated, time: .shortened))")
                }
            }

            Section {
                Toggle("Automatically check for updates", isOn: $updateChecker.automaticallyChecksForUpdates)
            } footer: {
                Text("Checks GitHub once a day when AppOrigins opens or becomes active. Downloads and installation are started by you.")
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }

    private var installedVersionLabel: String {
        if let installedVersion = updateChecker.installedVersion {
            return "Installed version \(installedVersion)"
        }
        return "Installed version unavailable"
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if updateChecker.isChecking {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Checking for updates")
        } else {
            Image(systemName: statusSymbol)
                .font(.title3)
                .foregroundStyle(statusColor)
                .accessibilityHidden(true)
        }
    }

    private var statusTitle: String {
        switch updateChecker.state {
        case .notChecked:
            return "Check for a newer version"
        case .checking:
            return "Checking GitHub…"
        case .upToDate:
            return "AppOrigins is up to date"
        case .updateAvailable:
            return "Update available"
        case .noRelease:
            return "No stable update available"
        case .unversioned:
            return "Version unavailable"
        case .failed:
            return "Couldn’t check for updates"
        }
    }

    private var statusDetail: String {
        switch updateChecker.state {
        case .notChecked:
            return "Compare this version with the latest public GitHub release."
        case .checking:
            return "Looking for the latest public release."
        case .upToDate:
            return "No newer release is available."
        case .updateAvailable:
            return "A newer version is ready. View the release notes or download the update."
        case .noRelease:
            return "No compatible stable release was found on GitHub."
        case .unversioned:
            return "This build has no release version to compare. You can browse releases on GitHub."
        case .failed:
            return updateChecker.lastCheckError ?? "The update check could not finish. Please try again."
        }
    }

    private var statusSymbol: String {
        switch updateChecker.state {
        case .upToDate:
            return "checkmark.circle"
        case .updateAvailable:
            return "arrow.down.circle"
        case .failed:
            return "exclamationmark.triangle"
        case .notChecked, .checking, .noRelease, .unversioned:
            return "info.circle"
        }
    }

    private var statusColor: Color {
        switch updateChecker.state {
        case .upToDate:
            return .green
        case .updateAvailable:
            return .accentColor
        case .failed:
            return .orange
        case .notChecked, .checking, .noRelease, .unversioned:
            return .secondary
        }
    }

    private var showsBrowseReleases: Bool {
        switch updateChecker.state {
        case .noRelease, .unversioned, .failed:
            return true
        case .notChecked, .checking, .upToDate, .updateAvailable:
            return false
        }
    }
}
