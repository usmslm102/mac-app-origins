import AppKit
import SwiftUI

@main
struct AppOriginsApp: App {
    @StateObject private var viewModel = AppScannerViewModel()

    init() {
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .task {
                    viewModel.refresh()
                }
        }
        .defaultSize(width: 1180, height: 760)
    }
}
