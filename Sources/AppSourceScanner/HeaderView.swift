import SwiftUI

struct HeaderView: View {
    @EnvironmentObject private var viewModel: AppScannerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(viewModel.sourceSummary)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(viewModel.scanScopeSummary)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}
