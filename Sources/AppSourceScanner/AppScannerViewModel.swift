import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum RefreshMode: String, CaseIterable, Identifiable {
    case quick = "Quick"
    case full = "Full"

    var id: Self { self }

    var scanMode: ScanMode {
        switch self {
        case .quick:
            return .quick
        case .full:
            return .full
        }
    }

    var actionLabel: String {
        switch self {
        case .quick:
            return "Quick Refresh"
        case .full:
            return "Full Rescan"
        }
    }
}

@MainActor
final class AppScannerViewModel: ObservableObject {
    private enum DefaultsKey {
        static let includeSystemApplications = "scan.includeSystemApplications"
        static let includeUserApplications = "scan.includeUserApplications"
        static let includeExternalVolumes = "scan.includeExternalVolumes"
        static let defaultRefreshMode = "scan.defaultRefreshMode"
        static let latestSnapshot = "activity.latestSnapshot.v1"
    }

    private let defaults: UserDefaults
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration = 0
    private var iconCache: [String: NSImage] = [:]
    private var appsByID: [InstalledApp.ID: InstalledApp] = [:]
    private var searchIndex: [InstalledApp.ID: String] = [:]
    private var previousSnapshot: ScanSnapshot?
    private var isUpdatingFilters = false

    @Published private(set) var apps: [InstalledApp] = []
    @Published private(set) var filteredApps: [InstalledApp] = []
    @Published private(set) var storageSummary = StorageSummary(apps: [])
    @Published private(set) var filteredSummary = "0 shown • 0 bytes total"
    @Published private(set) var sourceSummary = "Ready to scan your installed software"
    @Published private(set) var scanComparison: ScanComparison?
    @Published var searchText = "" { didSet { updateFilteredApps() } }
    @Published var selectedKindFilter: KindFilter = .all { didSet { updateFilteredApps() } }
    @Published var selectedSourceTab: SourceTab = .all { didSet { updateFilteredApps() } }
    @Published var selectedSecurityFilter: SecurityFilter = .all { didSet { updateFilteredApps() } }
    @Published var showDuplicatesOnly = false { didSet { updateFilteredApps() } }
    @Published var showExternalOnly = false { didSet { updateFilteredApps() } }
    @Published var defaultRefreshMode: RefreshMode = .quick {
        didSet {
            guard defaultRefreshMode != oldValue else { return }
            defaults.set(defaultRefreshMode.rawValue, forKey: DefaultsKey.defaultRefreshMode)
        }
    }
    @Published var includeSystemApplications = true {
        didSet {
            guard includeSystemApplications != oldValue else { return }
            persistScanScopeAndRefresh()
        }
    }
    @Published var includeUserApplications = true {
        didSet {
            guard includeUserApplications != oldValue else { return }
            persistScanScopeAndRefresh()
        }
    }
    @Published var includeExternalVolumes = false {
        didSet {
            guard includeExternalVolumes != oldValue else { return }
            persistScanScopeAndRefresh()
        }
    }
    @Published var sortOrder = [KeyPathComparator(\InstalledApp.name)] { didSet { updateFilteredApps() } }
    @Published var selectedAppID: InstalledApp.ID?
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?
    @Published private(set) var pendingTrashApp: InstalledApp?
    @Published private(set) var lastScanDate: Date?
    @Published private(set) var lastRefreshMode: RefreshMode = .quick
    @Published private(set) var lastScanDuration: TimeInterval?
    @Published private(set) var lastCacheHits = 0
    @Published private(set) var lastCacheMisses = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: DefaultsKey.latestSnapshot) {
            previousSnapshot = try? JSONDecoder().decode(ScanSnapshot.self, from: data)
        }
        includeSystemApplications = defaults.object(forKey: DefaultsKey.includeSystemApplications) as? Bool ?? true
        includeUserApplications = defaults.object(forKey: DefaultsKey.includeUserApplications) as? Bool ?? true
        includeExternalVolumes = defaults.object(forKey: DefaultsKey.includeExternalVolumes) as? Bool ?? false
        if let rawMode = defaults.string(forKey: DefaultsKey.defaultRefreshMode),
           let refreshMode = RefreshMode(rawValue: rawMode) {
            defaultRefreshMode = refreshMode
        }
    }

    private func updateFilteredApps() {
        guard !isUpdatingFilters else { return }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        filteredApps = apps.filter { app in
            let kindMatches = selectedKindFilter.kind.map { $0 == app.kind } ?? true
            let sourceMatches = selectedSourceTab.source.map { $0 == app.source } ?? true
            let securityMatches = selectedSecurityFilter.matches(app.securityStatus)
            let duplicateMatches = !showDuplicatesOnly || app.hasDuplicates
            let externalMatches = !showExternalOnly || app.isExternal
            guard kindMatches && sourceMatches && securityMatches && duplicateMatches && externalMatches else {
                return false
            }
            let searchMatches = query.isEmpty || searchIndex[app.id]?.localizedCaseInsensitiveContains(query) == true

            return searchMatches
        }
        .sorted(using: sortOrder)

        if let selectedAppID, !filteredApps.contains(where: { $0.id == selectedAppID }) {
            self.selectedAppID = nil
        }
        filteredSummary = makeFilteredSummary()
    }

    var hasActiveFilters: Bool {
        !searchText.isEmpty ||
            selectedKindFilter != .all ||
            selectedSourceTab != .all ||
            selectedSecurityFilter != .all ||
            showDuplicatesOnly ||
            showExternalOnly
    }

    private func makeSourceSummary() -> String {
        let grouped = Dictionary(grouping: apps, by: \.source)
        let appCount = apps.filter { $0.kind == .application }.count
        let cliCount = apps.filter { $0.kind == .cliTool }.count
        let homebrewCount = grouped[.homebrew]?.count ?? 0
        let appStoreCount = grouped[.appStore]?.count ?? 0
        let manualCount = grouped[.manual]?.count ?? 0
        let duplicateCount = apps.filter { $0.hasDuplicates }.count
        let externalCount = apps.filter(\.isExternal).count
        return "\(apps.count) items, \(appCount) apps, \(cliCount) CLI, \(homebrewCount) Homebrew, \(appStoreCount) App Store, \(manualCount) manual, \(externalCount) external, \(duplicateCount) duplicate copies"
    }

    private func makeFilteredSummary() -> String {
        let visibleApps = filteredApps
        let totalSize = visibleApps.compactMap(\.sizeInBytes).reduce(Int64(0), +)
        let unknownSizeCount = visibleApps.filter { $0.sizeInBytes == nil }.count
        let duplicateCount = visibleApps.filter { $0.hasDuplicates }.count

        var parts = [
            "\(visibleApps.count) shown",
            "\(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)) total"
        ]

        if duplicateCount > 0 {
            parts.append("\(duplicateCount) duplicates")
        }

        if unknownSizeCount > 0 {
            parts.append("\(unknownSizeCount) unknown size")
        }

        if hasActiveFilters {
            parts.append("filtered")
        }

        return parts.joined(separator: " • ")
    }

    var scanScopeSummary: String {
        var activeRoots: [String] = []
        if includeSystemApplications {
            activeRoots.append("/Applications")
        }
        if includeUserApplications {
            activeRoots.append("~/Applications")
        }
        if includeExternalVolumes {
            activeRoots.append("External volumes")
        }

        return activeRoots.isEmpty
            ? "No scan roots selected"
            : "Scanning: \(activeRoots.joined(separator: ", "))"
    }

    var lastScanLabel: String {
        guard let lastScanDate else {
            return "No scan completed yet"
        }

        let base = "Last \(lastRefreshMode.rawValue.lowercased()) scan: \(lastScanDate.formatted(date: .omitted, time: .shortened))"
        guard let lastScanDuration else {
            return base
        }

        return "\(base) (\(String(format: "%.1fs", lastScanDuration)))"
    }

    var scanPerformanceLabel: String {
        guard lastCacheHits + lastCacheMisses > 0 else {
            return "Metadata cache: no samples yet"
        }

        return "Metadata cache: \(lastCacheHits) hits • \(lastCacheMisses) recalculated"
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

    var selectedItemCanOpenInTerminal: Bool {
        canOpenInTerminal(withID: selectedAppID)
    }

    func refresh() {
        refresh(mode: defaultRefreshMode)
    }

    func refreshQuick() {
        refresh(mode: .quick)
    }

    func refreshFull() {
        refresh(mode: .full)
    }

    func clearFilters() {
        isUpdatingFilters = true
        searchText = ""
        selectedKindFilter = .all
        selectedSourceTab = .all
        selectedSecurityFilter = .all
        showDuplicatesOnly = false
        showExternalOnly = false
        isUpdatingFilters = false
        updateFilteredApps()
    }

    func selectActivityApp(path: String) {
        guard appsByID[path] != nil else { return }
        clearFilters()
        selectedAppID = path
    }

    var activitySummary: String {
        guard let scanComparison else { return "Scan Activity" }
        guard scanComparison.hasBaseline else { return "Baseline saved" }
        let count = scanComparison.changes.count
        return count == 0 ? "No changes" : "\(count) \(count == 1 ? "change" : "changes")"
    }

    private func refresh(mode: RefreshMode) {
        refreshTask?.cancel()
        refreshGeneration += 1
        let generation = refreshGeneration

        refreshTask = Task { [weak self] in
            await self?.performRefresh(generation: generation, mode: mode)
        }
    }

    private func performRefresh(generation: Int, mode: RefreshMode) async {
        isLoading = true
        lastError = nil
        let scanStart = Date()

        let scanner = AppScanner()
        let options = ScanOptions(
            includeSystemApplications: includeSystemApplications,
            includeUserApplications: includeUserApplications,
            includeExternalVolumes: includeExternalVolumes
        )

        let scanTask = Task.detached(priority: .userInitiated) {
            await scanner.scanApplications(options: options, mode: mode.scanMode)
        }
        let scanResult = await withTaskCancellationHandler {
            await scanTask.value
        } onCancel: {
            scanTask.cancel()
        }

        guard !Task.isCancelled, generation == refreshGeneration else {
            if generation == refreshGeneration {
                isLoading = false
            }
            return
        }

        applyScanResult(scanResult, options: options, mode: mode, startedAt: scanStart)
        isLoading = false
    }

    // Accept only completed, current-generation scans; cancelled scans never replace the baseline.
    func applyScanResult(_ scanResult: ScanResult, options: ScanOptions, mode: RefreshMode, startedAt: Date) {
        if mode == .full { iconCache.removeAll() }
        let installedApps = scanResult.apps.map(makeInstalledApp)
        let duplicateCounts = makeDuplicateCounts(for: installedApps)
        apps = installedApps.map { app in
            app.withDuplicateCount(duplicateCounts[app.id] ?? 1)
        }
        storageSummary = StorageSummary(apps: scanResult.apps)
        appsByID = apps.reduce(into: [:]) { $0[$1.id] = $1 }
        iconCache = iconCache.filter { appsByID[$0.key] != nil }
        searchIndex = apps.reduce(into: [:]) { index, app in
            index[app.id] = [
                app.name, app.typeLabel, app.bundleIdentifier, app.version,
                app.duplicateLabel, app.hasDuplicates ? "duplicate" : "",
                app.location, app.securityStatusLabel, app.sizeLabel, app.path, app.sourceLabel
            ].joined(separator: "\u{1F}")
        }
        sourceSummary = makeSourceSummary()
        updateFilteredApps()

        let completedAt = Date()
        lastScanDate = completedAt
        lastScanDuration = completedAt.timeIntervalSince(startedAt)
        lastRefreshMode = mode
        lastCacheHits = scanResult.cacheHits
        lastCacheMisses = scanResult.cacheMisses

        let snapshot = ScanSnapshot(
            apps: scanResult.apps,
            scope: ScanScope(
                includeSystemApplications: options.includeSystemApplications,
                includeUserApplications: options.includeUserApplications,
                includeExternalVolumes: options.includeExternalVolumes
            ),
            date: completedAt
        )
        scanComparison = ScanComparison(previous: previousSnapshot, current: snapshot)
        previousSnapshot = snapshot
        do {
            defaults.set(try JSONEncoder().encode(snapshot), forKey: DefaultsKey.latestSnapshot)
        } catch {
            lastError = "The scan completed, but its activity baseline could not be saved."
        }
    }

    func openSelectedApp() {
        openApp(withID: selectedAppID)
    }

    func openApp(withID appID: InstalledApp.ID?) {
        guard let app = app(for: appID), canOpen(app) else {
            lastError = "This item is not available to open."
            return
        }

        guard NSWorkspace.shared.open(URL(fileURLWithPath: app.path)) else {
            lastError = "Could not open \(app.name)."
            return
        }
    }

    func revealSelectedApp() {
        revealApp(withID: selectedAppID)
    }

    func revealApp(withID appID: InstalledApp.ID?) {
        guard let app = app(for: appID) else {
            return
        }
        guard FileManager.default.fileExists(atPath: app.path) else {
            lastError = "\(app.name) is no longer available at its previous path."
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.path)])
    }

    func openSelectedInTerminal() {
        openInTerminal(withID: selectedAppID)
    }

    func openInTerminal(withID appID: InstalledApp.ID?) {
        guard let app = app(for: appID) else {
            return
        }

        let targetPath: String
        if app.kind == .application {
            targetPath = URL(fileURLWithPath: app.path).deletingLastPathComponent().path
        } else {
            targetPath = app.path
        }

        guard FileManager.default.fileExists(atPath: targetPath) else {
            lastError = "Cannot open Terminal because \(targetPath) is not accessible."
            return
        }

        guard Shell.run("open", arguments: ["-a", "Terminal", targetPath]) != nil else {
            lastError = "Could not open Terminal at \(targetPath)."
            return
        }
    }

    func copySelectedPath() {
        copyPath(withID: selectedAppID)
    }

    func copySelectedIdentifier() {
        copyIdentifier(withID: selectedAppID)
    }

    func copyPath(withID appID: InstalledApp.ID?) {
        guard let app = app(for: appID) else { return }
        copyToPasteboard(app.path)
    }

    func copyIdentifier(withID appID: InstalledApp.ID?) {
        guard let app = app(for: appID) else { return }
        copyToPasteboard(app.bundleIdentifier)
    }

    func confirmMoveSelectedAppToTrash() {
        confirmMoveAppToTrash(withID: selectedAppID)
    }

    func confirmMoveAppToTrash(withID appID: InstalledApp.ID?) {
        guard let app = app(for: appID) else {
            return
        }

        guard FileManager.default.fileExists(atPath: app.path) else {
            lastError = "\(app.name) is no longer available at its previous path."
            return
        }

        guard canTrash(app) else {
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
            refresh()
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

    func canOpenInTerminal(withID appID: InstalledApp.ID?) -> Bool {
        guard let app = app(for: appID) else { return false }
        return canOpenInTerminal(app)
    }

    func exportCSV() {
        let rows = filteredApps.map { app in
            [
                app.name,
                app.kind.rawValue,
                app.bundleIdentifier,
                app.version,
                String(app.duplicateCount),
                app.securityStatusLabel,
                app.sizeLabel,
                app.source.rawValue,
                app.location,
                app.path
            ]
            .map(csvField)
            .joined(separator: ",")
        }

        let content = (["Name,Kind,Identifier,Version,DuplicateCount,SecurityStatus,Size,Source,Location,Path"] + rows).joined(separator: "\n")
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

    func exportScanActivity() {
        guard let scanComparison else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            export(content: try encoder.encode(scanComparison), defaultName: "apporigins-scan-activity", fileExtension: "json")
        } catch {
            lastError = "Could not export scan activity."
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
        panel.allowedContentTypes = [UTType(filenameExtension: fileExtension) ?? .data]

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

    private func makeInstalledApp(from scannedApp: ScannedApp) -> InstalledApp {
        if let cachedIcon = iconCache[scannedApp.path],
           appsByID[scannedApp.path]?.version == scannedApp.version {
            return InstalledApp(scannedApp: scannedApp, icon: cachedIcon)
        }

        let icon: NSImage
        switch scannedApp.kind {
        case .application:
            icon = NSWorkspace.shared.icon(forFile: scannedApp.path)
        case .cliTool:
            icon = cliIcon()
        }
        iconCache[scannedApp.path] = icon

        return InstalledApp(scannedApp: scannedApp, icon: icon)
    }

    private func persistScanScopeAndRefresh() {
        defaults.set(includeSystemApplications, forKey: DefaultsKey.includeSystemApplications)
        defaults.set(includeUserApplications, forKey: DefaultsKey.includeUserApplications)
        defaults.set(includeExternalVolumes, forKey: DefaultsKey.includeExternalVolumes)
        refresh()
    }

    private func app(for appID: InstalledApp.ID?) -> InstalledApp? {
        guard let appID else { return nil }
        return appsByID[appID]
    }

    private func canOpen(_ app: InstalledApp) -> Bool {
        guard app.kind == .application else { return false }
        return FileManager.default.fileExists(atPath: app.path)
    }

    private func canTrash(_ app: InstalledApp) -> Bool {
        guard app.kind == .application else { return false }
        guard FileManager.default.fileExists(atPath: app.path) else { return false }
        return FileManager.default.isDeletableFile(atPath: app.path)
    }

    private func canOpenInTerminal(_ app: InstalledApp) -> Bool {
        let path: String
        if app.kind == .application {
            path = URL(fileURLWithPath: app.path).deletingLastPathComponent().path
        } else {
            path = app.path
        }

        return FileManager.default.fileExists(atPath: path)
    }

    private func copyToPasteboard(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }

    private func makeDuplicateCounts(for apps: [InstalledApp]) -> [InstalledApp.ID: Int] {
        let keyedApps = apps.compactMap { app -> (InstalledApp, String)? in
            guard let key = duplicateKey(for: app) else {
                return nil
            }

            return (app, key)
        }

        let groups = Dictionary(grouping: keyedApps, by: { $0.1 })

        return groups.values.reduce(into: [:]) { partialResult, group in
            guard group.count > 1 else { return }

            for (app, _) in group {
                partialResult[app.id] = group.count
            }
        }
    }

    private func duplicateKey(for app: InstalledApp) -> String? {
        ScannerLogic.duplicateKey(
            kind: app.kind,
            bundleIdentifier: app.bundleIdentifier,
            name: app.name
        )
    }

    private func cliIcon() -> NSImage {
        if let symbolImage = NSImage(systemSymbolName: "terminal", accessibilityDescription: "CLI Tool") {
            return symbolImage
        }

        return NSWorkspace.shared.icon(for: .unixExecutable)
    }
}
