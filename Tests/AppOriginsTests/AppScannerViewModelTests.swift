import Foundation
import Testing
@testable import AppOrigins

@Suite @MainActor
struct AppScannerViewModelTests {
    @Test func filtersRefreshCachedResultsAndClearHiddenSelection() {
        let suite = "AppOriginsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppScannerViewModel(defaults: defaults)
        completeScan(model, apps: [item("Alpha", source: .appStore), item("Beta", source: .manual)])
        model.selectedAppID = "/Applications/Alpha.app"

        model.selectedSourceTab = .manual
        #expect(model.filteredApps.map(\.name) == ["Beta"])
        #expect(model.selectedApp == nil)
        #expect(model.filteredSummary.contains("1 shown"))

        model.clearFilters()
        model.searchText = "  beta  "
        #expect(model.filteredApps.map(\.name) == ["Beta"])
        model.searchText = "APP STORE"
        #expect(model.filteredApps.map(\.name) == ["Alpha"])
        model.searchText = ""
        model.sortOrder = [KeyPathComparator(\InstalledApp.name, order: .reverse)]
        #expect(model.filteredApps.map(\.name) == ["Beta", "Alpha"])
    }

    @Test func activityBaselineSurvivesRelaunchAndScopeChangesResetIt() throws {
        let suite = "AppOriginsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = AppScannerViewModel(defaults: defaults)
        completeScan(first, apps: [item("Alpha", version: "1.0")])
        #expect(first.scanComparison?.state == .initialBaseline)

        let relaunched = AppScannerViewModel(defaults: defaults)
        completeScan(relaunched, apps: [item("Alpha", version: "2.0"), item("Beta")])
        let comparison = try #require(relaunched.scanComparison)
        #expect(comparison.hasBaseline)
        #expect(comparison.changes.map(\.kind) == [.changed, .added])

        completeScan(relaunched, apps: [], options: ScanOptions(
            includeSystemApplications: false,
            includeUserApplications: true,
            includeExternalVolumes: false
        ))
        #expect(relaunched.scanComparison?.state == .scopeChanged)
        #expect(relaunched.scanComparison?.changes.isEmpty == true)
    }

    @Test func selectingActivityItemRestoresItsVisibility() {
        let suite = "AppOriginsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppScannerViewModel(defaults: defaults)
        completeScan(model, apps: [item("Alpha"), item("Beta")])
        model.searchText = "missing"
        model.showDuplicatesOnly = true
        #expect(model.filteredApps.isEmpty)

        model.selectActivityApp(path: "/Applications/Beta.app")
        #expect(!model.hasActiveFilters)
        #expect(model.selectedApp?.name == "Beta")
        #expect(model.filteredApps.count == 2)
    }

    @Test func refreshedInventoryInvalidatesSearchAndRemovesStaleSelection() {
        let suite = "AppOriginsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppScannerViewModel(defaults: defaults)
        completeScan(model, apps: [item("Alpha", version: "1.0"), item("Beta")])
        model.selectedAppID = "/Applications/Beta.app"
        completeScan(model, apps: [item("Alpha", version: "2.0")])

        #expect(model.selectedApp == nil)
        model.searchText = "1.0"
        #expect(model.filteredApps.isEmpty)
        model.searchText = "2.0"
        #expect(model.filteredApps.map(\.name) == ["Alpha"])
        #expect(model.filteredSummary.contains("1 shown"))
        #expect(model.sourceSummary.contains("1 items"))
    }

    @Test func storageSummaryAlwaysCoversFullInventoryRegardlessOfFilters() {
        let suite = "AppOriginsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppScannerViewModel(defaults: defaults)
        completeScan(model, apps: [
            item("Alpha", source: .appStore, size: 1_024),
            item("Alpha Copy", size: 2_048, external: true, identifier: "com.test.Alpha"),
            item("tool", source: .homebrew, kind: .cliTool, size: nil)
        ])
        let summary = model.storageSummary
        #expect(summary.total.itemCount == 3)
        #expect(summary.total.sizeInBytes == 3_072)
        #expect(summary.total.unknownSizeCount == 1)
        #expect(model.apps.filter(\.hasDuplicates).count == 2)

        model.searchText = "Alpha"
        #expect(model.filteredApps.count == 2)
        #expect(model.storageSummary == summary)
        model.clearFilters()
        model.selectedSourceTab = .appStore
        #expect(model.filteredApps.count == 1)
        #expect(model.storageSummary == summary)
        model.clearFilters()
        model.selectedKindFilter = .cliTools
        #expect(model.filteredApps.count == 1)
        #expect(model.storageSummary == summary)
        model.clearFilters()
        model.selectedSecurityFilter = .unsigned
        #expect(model.filteredApps.isEmpty)
        #expect(model.storageSummary == summary)
        model.clearFilters()
        model.showDuplicatesOnly = true
        #expect(model.filteredApps.count == 2)
        #expect(model.storageSummary == summary)
        model.clearFilters()
        model.showExternalOnly = true
        #expect(model.filteredApps.count == 1)
        #expect(model.storageSummary == summary)
        model.sortOrder = [KeyPathComparator(\InstalledApp.name, order: .reverse)]
        #expect(model.storageSummary == summary)
    }

    @Test func storageSummaryReplacesSizesAndRemovesMissingInstallationsAfterRefresh() {
        let suite = "AppOriginsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppScannerViewModel(defaults: defaults)
        completeScan(model, apps: [
            item("Alpha", size: 100),
            item("Beta", source: .homebrew, size: 200, external: true)
        ])
        #expect(model.storageSummary.total.sizeInBytes == 300)
        #expect(model.storageSummary.externalStorage.itemCount == 1)

        model.searchText = "Beta"
        completeScan(model, apps: [item("Alpha", version: "2.0", size: 900)])
        #expect(model.filteredApps.isEmpty)
        #expect(model.storageSummary.total.itemCount == 1)
        #expect(model.storageSummary.total.sizeInBytes == 900)
        #expect(model.storageSummary.internalStorage.sizeInBytes == 900)
        #expect(model.storageSummary.externalStorage.itemCount == 0)
        #expect(model.storageSummary.bySource.first { $0.source == .homebrew }?.total.itemCount == 0)

        completeScan(model, apps: [])
        #expect(model.storageSummary == StorageSummary(apps: []))
    }

    private func completeScan(_ model: AppScannerViewModel, apps: [ScannedApp], options: ScanOptions = .default) {
        model.applyScanResult(
            ScanResult(apps: apps, cacheHits: 0, cacheMisses: apps.count),
            options: options,
            mode: .quick,
            startedAt: Date()
        )
    }

    private func item(
        _ name: String,
        version: String = "1.0",
        source: AppSource = .manual,
        kind: InstallKind = .application,
        size: Int64? = 1_024,
        external: Bool = false,
        identifier: String? = nil
    ) -> ScannedApp {
        ScannedApp(
            name: name, kind: kind, bundleIdentifier: identifier ?? "com.test.\(name)",
            version: version, securityStatus: .signed, sizeInBytes: size,
            path: "\(external ? "/Volumes/External" : "")/Applications/\(name).app", source: source,
            location: external ? "External" : "Internal Disk", isExternal: external
        )
    }
}
