import AppKit
import SwiftUI

struct AppTableView: View {
    @EnvironmentObject private var viewModel: AppScannerViewModel

    var body: some View {
        Table(viewModel.filteredApps, selection: $viewModel.selectedAppID, sortOrder: $viewModel.sortOrder) {
            TableColumn("Item", value: \.name) { app in
                HStack(spacing: 8) {
                    Image(nsImage: app.icon)
                        .resizable()
                        .frame(width: 22, height: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(app.name)
                            .lineLimit(1)
                        if app.hasDuplicates {
                            Text("\(app.duplicateLabel) copies")
                                .font(.system(size: 10))
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .width(min: 200, ideal: 250)

            TableColumn("Version", value: \.version) { app in
                Text(app.version)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 100, ideal: 120)

            TableColumn("Size", value: \.sizeSortValue) { app in
                Text(app.sizeLabel)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .width(min: 80, ideal: 100)

            TableColumn("Source", value: \.sourceLabel) { app in
                SourceBadge(source: app.source)
            }
            .width(min: 120, ideal: 140)

            TableColumn("Security", value: \.securityStatusLabel) { app in
                SecurityBadge(status: app.securityStatus)
            }
            .width(min: 130, ideal: 150)

            TableColumn("Location", value: \.locationLabel) { app in
                Text(app.location)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 120, ideal: 150)

            TableColumn("Type", value: \.typeLabel) { app in
                Text(app.kind.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 100)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contextMenu(forSelectionType: InstalledApp.ID.self) { items in
            contextMenuContent(for: items.first ?? viewModel.selectedAppID)
        } primaryAction: { items in
            viewModel.openApp(withID: items.first ?? viewModel.selectedAppID)
        }
    }

    @ViewBuilder
    private func contextMenuContent(for targetAppID: InstalledApp.ID?) -> some View {
        if viewModel.canOpenApp(withID: targetAppID) {
            Button("Open") { viewModel.openApp(withID: targetAppID) }
        }
        Button("Reveal in Finder") { viewModel.revealApp(withID: targetAppID) }
            .disabled(targetAppID == nil)
        Button("Open in Terminal") { viewModel.openInTerminal(withID: targetAppID) }
            .disabled(!viewModel.canOpenInTerminal(withID: targetAppID))
        Divider()
        Button("Copy Path") { viewModel.copyPath(withID: targetAppID) }
            .disabled(targetAppID == nil)
        Button("Copy Identifier") { viewModel.copyIdentifier(withID: targetAppID) }
            .disabled(targetAppID == nil)
        Divider()
        Button("Move to Trash", role: .destructive) { viewModel.confirmMoveAppToTrash(withID: targetAppID) }
            .disabled(!viewModel.canTrashApp(withID: targetAppID))
    }
}
