import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var viewModel: AppScannerViewModel

    var body: some View {
        TabView {
            scanSettings
                .tabItem {
                    Label("Scanning", systemImage: "magnifyingglass")
                }

            refreshSettings
                .tabItem {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
        }
        .frame(width: 460, height: 300)
    }

    private var scanSettings: some View {
        Form {
            Section {
                Toggle(isOn: $viewModel.includeSystemApplications) {
                    settingsLabel(
                        "System Applications",
                        detail: "Scan apps installed in /Applications."
                    )
                }

                Toggle(isOn: $viewModel.includeUserApplications) {
                    settingsLabel(
                        "User Applications",
                        detail: "Scan apps installed in ~/Applications."
                    )
                }

                Toggle(isOn: $viewModel.includeExternalVolumes) {
                    settingsLabel(
                        "External Volumes",
                        detail: "Include app folders on attached local volumes."
                    )
                }
            } header: {
                Text("Scan Locations")
            } footer: {
                Text(viewModel.scanScopeSummary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }

    private var refreshSettings: some View {
        Form {
            Section {
                Picker("Default refresh", selection: $viewModel.defaultRefreshMode) {
                    ForEach(RefreshMode.allCases) { mode in
                        Text(mode.actionLabel).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)

                Divider()

                Button {
                    viewModel.refresh()
                } label: {
                    Label("Refresh Now", systemImage: "arrow.clockwise")
                }
            } header: {
                Text("Refresh Behavior")
            } footer: {
                Text(viewModel.scanPerformanceLabel)
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }

    private func settingsLabel(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    private init() {}

    func open(viewModel: AppScannerViewModel) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingController = NSHostingController(
            rootView: SettingsView()
                .environmentObject(viewModel)
        )

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("AppOriginsSettings")
        window.delegate = SettingsWindowDelegate.shared
        SettingsWindowDelegate.shared.onClose = { [weak self] in
            self?.window = nil
        }

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
private final class SettingsWindowDelegate: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowDelegate()
    var onClose: (() -> Void)?

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}
