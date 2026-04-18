import SwiftUI

struct StatusBarView: View {
    @EnvironmentObject private var viewModel: AppScannerViewModel

    var body: some View {
        HStack(spacing: 0) {
            Text(viewModel.filteredSummary)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer()

            if viewModel.isLoading {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Scanning…")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity)
            } else {
                Text(viewModel.lastScanLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.isLoading)
    }
}
