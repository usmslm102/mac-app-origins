import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppScannerViewModel: ObservableObject {
    @Published private(set) var apps: [InstalledApp] = []
    @Published var searchText = ""
    @Published var selectedKindFilter: KindFilter = .all
    @Published var selectedSourceFilter: SourceFilter = .all
    @Published var selectedAppID: InstalledApp.ID?
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?
    @Published private(set) var pendingTrashApp: InstalledApp?

    var filteredApps: [InstalledApp] {
        apps.filter { app in
            let kindMatches = selectedKindFilter.kind.map { $0 == app.kind } ?? true
            let sourceMatches = selectedSourceFilter.source.map { $0 == app.source } ?? true
            let searchMatches = searchText.isEmpty || [
                app.name,
                app.kind.rawValue,
                app.bundleIdentifier,
                app.version,
                app.path,
                app.source.rawValue
            ].contains { $0.localizedCaseInsensitiveContains(searchText) }

            return kindMatches && sourceMatches && searchMatches
        }
    }

    var sourceSummary: String {
        let grouped = Dictionary(grouping: apps, by: \.source)
        let appCount = apps.filter { $0.kind == .application }.count
        let cliCount = apps.filter { $0.kind == .cliTool }.count
        let homebrewCount = grouped[.homebrew]?.count ?? 0
        let appStoreCount = grouped[.appStore]?.count ?? 0
        let manualCount = grouped[.manual]?.count ?? 0
        return "\(apps.count) items, \(appCount) apps, \(cliCount) CLI, \(homebrewCount) Homebrew, \(appStoreCount) App Store, \(manualCount) manual"
    }

    var selectedApp: InstalledApp? {
        app(for: selectedAppID)
    }

    var selectedItemCanOpen: Bool {
        canOpenApp(withID: selectedAppID)
    }

    var selectedItemCanTrash: Bool {
        canTrashApp(withID: selectedAppID)
    }

    func refresh() async {
        isLoading = true
        lastError = nil

        let scanner = AppScanner()
        let scannedApps = await Task.detached(priority: .userInitiated) {
            scanner.scanApplications()
        }.value

        apps = scannedApps
        if let selectedAppID, !apps.contains(where: { $0.id == selectedAppID }) {
            self.selectedAppID = nil
        }
        isLoading = false
    }

    func openSelectedApp() {
        openApp(withID: selectedAppID)
    }

    func openApp(withID appID: InstalledApp.ID?) {
        guard let app = app(for: appID), canOpen(app) else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: app.path))
    }

    func revealSelectedApp() {
        revealApp(withID: selectedAppID)
    }

    func revealApp(withID appID: InstalledApp.ID?) {
        guard let app = app(for: appID) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.path)])
    }

    func confirmMoveSelectedAppToTrash() {
        confirmMoveAppToTrash(withID: selectedAppID)
    }

    func confirmMoveAppToTrash(withID appID: InstalledApp.ID?) {
        guard let app = app(for: appID), canTrash(app) else {
            lastError = "You do not have permission to move this app to Trash."
            return
        }

        pendingTrashApp = app
    }

    func movePendingAppToTrash() async {
        guard let pendingTrashApp, pendingTrashApp.kind == .application else { return }
        guard canTrash(pendingTrashApp) else {
            lastError = "You do not have permission to move \(pendingTrashApp.name) to Trash."
            self.pendingTrashApp = nil
            return
        }

        do {
            let appURL = URL(fileURLWithPath: pendingTrashApp.path)
            _ = try FileManager.default.trashItem(at: appURL, resultingItemURL: nil)
            self.pendingTrashApp = nil
            await refresh()
        } catch {
            lastError = "Could not move \(pendingTrashApp.name) to Trash."
            self.pendingTrashApp = nil
        }
    }

    func dismissTrashConfirmation() {
        pendingTrashApp = nil
    }

    func dismissError() {
        lastError = nil
    }

    func canOpenApp(withID appID: InstalledApp.ID?) -> Bool {
        guard let app = app(for: appID) else { return false }
        return canOpen(app)
    }

    func canTrashApp(withID appID: InstalledApp.ID?) -> Bool {
        guard let app = app(for: appID) else { return false }
        return canTrash(app)
    }

    func exportCSV() {
        let rows = filteredApps.map { app in
            [
                app.name,
                app.kind.rawValue,
                app.bundleIdentifier,
                app.version,
                app.source.rawValue,
                app.path
            ]
            .map(csvField)
            .joined(separator: ",")
        }

        let content = (["Name,Kind,Identifier,Version,Source,Path"] + rows).joined(separator: "\n")
        export(content: content.data(using: .utf8), defaultName: "installed-app-sources", fileExtension: "csv")
    }

    func exportJSON() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let data = try encoder.encode(filteredApps.map(ExportedApp.init))
            export(content: data, defaultName: "installed-app-sources", fileExtension: "json")
        } catch {
            lastError = "Could not export JSON."
        }
    }

    private func export(content: Data?, defaultName: String, fileExtension: String) {
        guard let content else {
            lastError = "Nothing to export."
            return
        }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(defaultName).\(fileExtension)"
        if let contentType = UTType(filenameExtension: fileExtension) {
            panel.allowedContentTypes = [contentType]
        } else {
            panel.allowedFileTypes = [fileExtension]
        }

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            try content.write(to: url, options: .atomic)
        } catch {
            lastError = "Could not save \(url.lastPathComponent)."
        }
    }

    private func csvField(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private func app(for appID: InstalledApp.ID?) -> InstalledApp? {
        guard let appID else { return nil }
        return apps.first(where: { $0.id == appID })
    }

    private func canOpen(_ app: InstalledApp) -> Bool {
        app.kind == .application
    }

    private func canTrash(_ app: InstalledApp) -> Bool {
        guard app.kind == .application else { return false }
        return FileManager.default.isDeletableFile(atPath: app.path)
    }
}

struct ContentView: View {
    @EnvironmentObject private var viewModel: AppScannerViewModel
    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            filters
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .alert("Move App to Trash?", isPresented: moveToTrashAlertBinding, presenting: viewModel.pendingTrashApp) { app in
            Button("Cancel", role: .cancel) {
                viewModel.dismissTrashConfirmation()
            }
            Button("Move to Trash", role: .destructive) {
                Task {
                    await viewModel.movePendingAppToTrash()
                }
            }
        } message: { app in
            Text("This moves \(app.name) to Trash. App support files are not removed.")
        }
        .alert("Action Failed", isPresented: errorAlertBinding) {
            Button("OK") {
                viewModel.dismissError()
            }
        } message: {
            Text(viewModel.lastError ?? "Unknown error")
        }
        .onAppear {
            DispatchQueue.main.async {
                searchFieldFocused = true
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Installed Software Sources")
                    .font(.system(size: 24, weight: .semibold))
                Text(viewModel.sourceSummary)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 12) {
                searchField

                HStack(spacing: 10) {
                    if viewModel.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Menu("Export") {
                        Button("Export CSV") {
                            viewModel.exportCSV()
                        }
                        Button("Export JSON") {
                            viewModel.exportJSON()
                        }
                    }

                    Button("Open") {
                        viewModel.openSelectedApp()
                    }
                    .disabled(!viewModel.selectedItemCanOpen)

                    Button("Reveal") {
                        viewModel.revealSelectedApp()
                    }
                    .disabled(viewModel.selectedApp == nil)

                    Button("Trash") {
                        viewModel.confirmMoveSelectedAppToTrash()
                    }
                    .disabled(!viewModel.selectedItemCanTrash)

                    Button("Refresh") {
                        Task {
                            await viewModel.refresh()
                        }
                    }
                    .keyboardShortcut("r", modifiers: [.command])
                }
            }
        }
    }

    private var filters: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Type")
                    .font(.headline)

                Picker("Type", selection: $viewModel.selectedKindFilter) {
                    ForEach(KindFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Source")
                    .font(.headline)

                Picker("Source", selection: $viewModel.selectedSourceFilter) {
                    ForEach(SourceFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 420)
            }

            Spacer()

            Text("\(viewModel.filteredApps.count) shown")
                .foregroundStyle(.secondary)
        }
    }

    private var content: some View {
        HSplitView {
            table
            detailsPanel
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .layoutPriority(1)
    }

    private var table: some View {
        Table(viewModel.filteredApps, selection: $viewModel.selectedAppID) {
            TableColumn("Item") { app in
                HStack(spacing: 10) {
                    Image(nsImage: app.icon)
                        .resizable()
                        .frame(width: 20, height: 20)
                    Text(app.name)
                }
            }
            .width(min: 220, ideal: 260)

            TableColumn("Version") { app in
                Text(app.version)
                    .foregroundStyle(.secondary)
            }
            .width(min: 110, ideal: 130)

            TableColumn("Type") { app in
                Text(app.kind.rawValue)
                    .foregroundStyle(.secondary)
            }
            .width(min: 110, ideal: 120)

            TableColumn("Source") { app in
                Text(app.source.rawValue)
            }
            .width(min: 130, ideal: 150)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contextMenu(forSelectionType: InstalledApp.ID.self) { items in
            let targetAppID = items.first ?? viewModel.selectedAppID

            if viewModel.canOpenApp(withID: targetAppID) {
                Button("Open") {
                    viewModel.openApp(withID: targetAppID)
                }
            }
            Button("Reveal in Finder") {
                viewModel.revealApp(withID: targetAppID)
            }
            .disabled(targetAppID == nil)
            Divider()
            Button("Move to Trash", role: .destructive) {
                viewModel.confirmMoveAppToTrash(withID: targetAppID)
            }
            .disabled(!viewModel.canTrashApp(withID: targetAppID))
        } primaryAction: { items in
            let targetAppID = items.first ?? viewModel.selectedAppID
            viewModel.openApp(withID: targetAppID)
        }
    }

    private var detailsPanel: some View {
        Group {
            if let app = viewModel.selectedApp {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Image(nsImage: app.icon)
                            .resizable()
                            .frame(width: 48, height: 48)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(app.name)
                                .font(.title3.weight(.semibold))
                            Text("\(app.kind.rawValue) • \(app.source.rawValue)")
                                .foregroundStyle(.secondary)
                        }
                    }

                    detailRow("Type", value: app.kind.rawValue)
                    detailRow("Version", value: app.version)
                    detailRow(app.identifierLabel, value: app.bundleIdentifier)
                    detailRow("Path", value: app.path, mono: true)

                    Spacer()
                }
                .padding(18)
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 360, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("Select an App")
                        .font(.title3.weight(.semibold))
                    Text("Choose a row to open it, reveal it in Finder, export data, or move it to Trash.")
                        .foregroundStyle(.secondary)
                }
                .padding(18)
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 360, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private func detailRow(_ title: String, value: String, mono: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
                .font(mono ? .system(.body, design: .monospaced) : .body)
        }
    }

    private var moveToTrashAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.pendingTrashApp != nil },
            set: { newValue in
                if !newValue {
                    viewModel.dismissTrashConfirmation()
                }
            }
        )
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.lastError != nil },
            set: { newValue in
                if !newValue {
                    viewModel.dismissError()
                }
            }
        )
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search name, type, source, identifier, version, or path", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .focused($searchFieldFocused)

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                    searchFieldFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 420)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
    }
}
