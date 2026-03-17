import SwiftUI

@main
struct AppSourceScannerApp: App {
    @StateObject private var viewModel = AppScannerViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .task {
                    await viewModel.refresh()
                }
        }
        .defaultSize(width: 1180, height: 760)
    }
}
