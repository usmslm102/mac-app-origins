import AppKit
import SwiftUI

struct DetailPanelView: View {
    @EnvironmentObject private var viewModel: AppScannerViewModel

    var body: some View {
        Group {
            if let app = viewModel.selectedApp {
                selectedAppDetail(app)
                    .id(app.id)
                    .transition(.opacity)
            } else {
                emptySelection
            }
        }
        .frame(minWidth: 260, idealWidth: 300, maxWidth: 340, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .animation(.easeInOut(duration: 0.2), value: viewModel.selectedAppID)
    }

    private func selectedAppDetail(_ app: InstalledApp) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // App icon and name header
                VStack(spacing: 12) {
                    Image(nsImage: app.icon)
                        .resizable()
                        .frame(width: 64, height: 64)
                        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)

                    VStack(spacing: 6) {
                        Text(app.name)
                            .font(.title3.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)

                        HStack(spacing: 6) {
                            SourceBadge(source: app.source)
                            SecurityBadge(status: app.securityStatus)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)

                Divider().padding(.horizontal, 16)

                // Detail rows
                VStack(alignment: .leading, spacing: 14) {
                    detailRow("Type", value: app.kind.rawValue)
                    detailRow("Version", value: app.version)
                    if app.hasDuplicates {
                        detailRow("Copies", value: "\(app.duplicateCount) installed")
                    }
                    detailRow("Size", value: app.sizeLabel)
                    detailRow("Location", value: app.location)
                    detailRow(app.identifierLabel, value: app.bundleIdentifier)
                    detailRow("Path", value: app.path, mono: true)
                }
                .padding(16)

                Divider().padding(.horizontal, 16)

                // Action buttons
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        if viewModel.canOpenApp(withID: app.id) {
                            actionButton("Open", icon: "arrow.up.forward.app") {
                                viewModel.openApp(withID: app.id)
                            }
                        }
                        actionButton("Reveal", icon: "folder") {
                            viewModel.revealApp(withID: app.id)
                        }
                        if viewModel.canOpenInTerminal(withID: app.id) {
                            actionButton("Terminal", icon: "terminal") {
                                viewModel.openInTerminal(withID: app.id)
                            }
                        }
                    }

                    if viewModel.canTrashApp(withID: app.id) {
                        Button(role: .destructive) {
                            viewModel.confirmMoveAppToTrash(withID: app.id)
                        } label: {
                            Label("Move to Trash", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .controlSize(.small)
                    }
                }
                .padding(16)
            }
        }
    }

    private var emptySelection: some View {
        VStack(spacing: 14) {
            Image(systemName: "app.dashed")
                .font(.system(size: 36))
                .foregroundStyle(.quaternary)
            Text("No Selection")
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
            Text("Select an app to view details and actions.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func detailRow(_ title: String, value: String, mono: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            Text(value)
                .textSelection(.enabled)
                .font(mono ? .system(size: 12, design: .monospaced) : .system(size: 13))
                .lineLimit(mono ? 4 : 2)
                .truncationMode(.middle)
        }
    }

    private func actionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .controlSize(.small)
    }
}
