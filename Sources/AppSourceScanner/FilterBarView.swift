import SwiftUI

struct FilterBarView: View {
    @EnvironmentObject private var viewModel: AppScannerViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                Picker("Type", selection: $viewModel.selectedKindFilter) {
                    ForEach(KindFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)

                Divider().frame(height: 22)

                Picker("Source", selection: $viewModel.selectedSourceTab) {
                    ForEach(SourceTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 400)

                Divider().frame(height: 22)

                Toggle("Duplicates", isOn: $viewModel.showDuplicatesOnly)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .fixedSize()

                Toggle("External", isOn: $viewModel.showExternalOnly)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .fixedSize()
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
