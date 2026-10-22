import SwiftUI

struct StorageOverviewView: View {
    @EnvironmentObject private var viewModel: AppScannerViewModel
    @State private var showingBreakdown = false

    private var summary: StorageSummary { viewModel.storageSummary }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if viewModel.lastScanDate == nil {
                HStack(spacing: 8) {
                    if viewModel.isLoading {
                        ProgressView().controlSize(.small)
                    }
                    Label(
                        viewModel.isLoading ? "Calculating overall sizes…" : "Scan to see overall sizes",
                        systemImage: "externaldrive"
                    )
                    .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 20) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 24) {
                            overallSize
                            kindSizes
                        }
                        overallSize
                    }

                    Button {
                        showingBreakdown.toggle()
                    } label: {
                        Label("Size Breakdown", systemImage: "chart.bar.xaxis")
                    }
                    .controlSize(.small)
                    .disabled(summary.total.itemCount == 0)
                    .help("See overall sizes by source, install type and storage location")
                    .popover(isPresented: $showingBreakdown, arrowEdge: .bottom) {
                        StorageBreakdownView(summary: summary)
                    }

                    Spacer(minLength: 0)
                }

                Text(scopeNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }

    private var overallSize: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Label(
                summary.total.unknownSizeCount > 0 ? "Overall measured size" : "Overall size",
                systemImage: "externaldrive"
            )
            .foregroundStyle(.secondary)
            Text(summary.total.sizeLabel)
                .font(.headline)
                .monospacedDigit()
                .textSelection(.enabled)
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
    }

    private var kindSizes: some View {
        HStack(spacing: 20) {
            compactSize("Apps", total: summary.applications)
            compactSize("CLI tools", total: summary.cliTools)
        }
    }

    private func compactSize(_ title: String, total: StorageSizeTotal) -> some View {
        HStack(spacing: 6) {
            Text(title).foregroundStyle(.secondary)
            Text(total.sizeLabel).monospacedDigit()
        }
        .font(.callout)
        .fixedSize()
        .accessibilityElement(children: .combine)
    }

    private var scopeNote: String {
        var note = "All \(summary.total.itemCount) scanned items, including every installed copy."
        if summary.total.unknownSizeCount > 0 {
            note += " \(summary.total.unknownSizeCount) with unknown size excluded from totals."
        }
        if viewModel.isLoading {
            note += " Updating scan…"
        } else if viewModel.hasActiveFilters {
            note += " Filtered size is shown below the list."
        }
        return note
    }
}

private struct StorageBreakdownView: View {
    let summary: StorageSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Size Breakdown")
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("All scanned apps and CLI tools, regardless of search or filters.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            sizeRow("Overall", total: summary.total, emphasized: true)
            Divider()

            VStack(alignment: .leading, spacing: 10) {
                sectionHeading("By source")
                ForEach(summary.bySource) { group in
                    sizeRow(group.source.rawValue, total: group.total)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                sectionHeading("By install type")
                sizeRow("Applications", total: summary.applications)
                sizeRow("CLI tools", total: summary.cliTools)
            }

            VStack(alignment: .leading, spacing: 10) {
                sectionHeading("By location")
                sizeRow("Internal disk", total: summary.internalStorage)
                sizeRow("External volumes", total: summary.externalStorage)
            }

            Divider()
            Text("Sizes cover scanned app bundles and Homebrew formula folders. Support files and other disk contents are outside this scan. Unknown sizes are excluded from totals; each installed copy counts separately.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 420)
    }

    private func sectionHeading(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .accessibilityAddTraits(.isHeader)
    }

    private func sizeRow(_ title: String, total: StorageSizeTotal, emphasized: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(emphasized ? .semibold : .regular)
                Text(itemCountLabel(total))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Text(total.sizeLabel)
                .fontWeight(emphasized ? .semibold : .regular)
                .monospacedDigit()
                .textSelection(.enabled)
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
    }

    private func itemCountLabel(_ total: StorageSizeTotal) -> String {
        let items = total.itemCount == 1 ? "1 item" : "\(total.itemCount) items"
        guard total.unknownSizeCount > 0 else { return items }
        return "\(items) · \(total.unknownSizeCount) unknown size"
    }
}
