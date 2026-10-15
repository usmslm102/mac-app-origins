import AppKit
import SwiftUI

@main
struct AppOriginsApp: App {
    @StateObject private var viewModel = AppScannerViewModel()
    @StateObject private var updateChecker = AppUpdateChecker()

    init() {
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .environmentObject(updateChecker)
                .task {
                    viewModel.refresh()
                    await updateChecker.checkIfNeeded()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    Task { await updateChecker.checkIfNeeded() }
                }
        }
        .defaultSize(width: 1180, height: 760)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    SettingsWindowController.shared.open(viewModel: viewModel, updateChecker: updateChecker, tab: .updates)
                    Task { await updateChecker.checkForUpdates() }
                }
                .disabled(updateChecker.isChecking)
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    SettingsWindowController.shared.open(viewModel: viewModel, updateChecker: updateChecker)
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }
    }
}
