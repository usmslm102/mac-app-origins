import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: AppScannerViewModel
    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    HeaderView()
                    Spacer()
                    searchField
                }
                FilterBarView()
                contentArea
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 10)

            StatusBarView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .toolbar { toolbarContent }
        .alert("Move App to Trash?", isPresented: moveToTrashBinding, presenting: viewModel.pendingTrashApp) { app in
            Button("Cancel", role: .cancel) { viewModel.dismissTrashConfirmation() }
            Button("Move to Trash", role: .destructive) {
                Task { await viewModel.movePendingAppToTrash() }
            }
        } message: { app in
            Text("This moves \(app.name) to Trash. App support files are not removed.")
        }
        .alert("Action Failed", isPresented: errorBinding) {
            Button("OK") { viewModel.dismissError() }
        } message: {
            Text(viewModel.lastError ?? "Unknown error")
        }
        .onAppear {
            DispatchQueue.main.async { searchFieldFocused = true }
        }
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        if viewModel.apps.isEmpty && (viewModel.isLoading || viewModel.lastScanDate == nil) {
            loadingView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
        } else if viewModel.filteredApps.isEmpty {
            emptyResultsView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
        } else {
            HSplitView {
                AppTableView()
                DetailPanelView()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .layoutPriority(1)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Scanning applications…")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(viewModel.scanScopeSummary)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var emptyResultsView: some View {
        VStack(spacing: 14) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.quaternary)
            Text("No Results")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Try adjusting your search or filters.")
                .foregroundStyle(.tertiary)

            if viewModel.hasActiveFilters {
                Button {
                    viewModel.clearFilters()
                    searchFieldFocused = true
                } label: {
                    Label("Clear Filters", systemImage: "line.3.horizontal.decrease.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            Button {
                SettingsWindowController.shared.open(viewModel: viewModel)
            } label: {
                Label("Settings", systemImage: "gearshape")
            }

            Button { viewModel.openSelectedApp() } label: {
                Label("Open", systemImage: "arrow.up.forward.app")
            }
            .keyboardShortcut("o", modifiers: [.command])
            .disabled(!viewModel.selectedItemCanOpen)

            Button { viewModel.revealSelectedApp() } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .disabled(viewModel.selectedApp == nil)

            Button { viewModel.openSelectedInTerminal() } label: {
                Label("Open in Terminal", systemImage: "terminal")
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(!viewModel.selectedItemCanOpenInTerminal)

            Button { viewModel.confirmMoveSelectedAppToTrash() } label: {
                Label("Move to Trash", systemImage: "trash")
            }
            .keyboardShortcut(.delete, modifiers: [.command])
            .disabled(!viewModel.selectedItemCanTrash)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Button("Copy Path") { viewModel.copySelectedPath() }
                    .disabled(viewModel.selectedApp == nil)
                Button("Copy Identifier") { viewModel.copySelectedIdentifier() }
                    .disabled(viewModel.selectedApp == nil)
                Divider()
                Button("Export CSV") { viewModel.exportCSV() }
                Button("Export JSON") { viewModel.exportJSON() }
            } label: {
                Label("Export & Copy", systemImage: "square.and.arrow.up")
            }

            Button { viewModel.refresh() } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: [.command])
        }
    }

    // MARK: - Search Field

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 13))

            TextField("Search…", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .focused($searchFieldFocused)
                .font(.system(size: 13))

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                    searchFieldFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(width: 260)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
        }
    }

    // MARK: - Alert Bindings

    private var moveToTrashBinding: Binding<Bool> {
        Binding(
            get: { viewModel.pendingTrashApp != nil },
            set: { if !$0 { viewModel.dismissTrashConfirmation() } }
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.lastError != nil },
            set: { if !$0 { viewModel.dismissError() } }
        )
    }
}
