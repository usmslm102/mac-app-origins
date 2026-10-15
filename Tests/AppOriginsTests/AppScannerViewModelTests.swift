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

    private func completeScan(_ model: AppScannerViewModel, apps: [ScannedApp], options: ScanOptions = .default) {
        model.applyScanResult(
            ScanResult(apps: apps, cacheHits: 0, cacheMisses: apps.count),
            options: options,
            mode: .quick,
            startedAt: Date()
        )
    }

    private func item(_ name: String, version: String = "1.0", source: AppSource = .manual) -> ScannedApp {
        ScannedApp(
            name: name, kind: .application, bundleIdentifier: "com.test.\(name)",
            version: version, securityStatus: .signed, sizeInBytes: 1024,
            path: "/Applications/\(name).app", source: source,
            location: "Internal Disk", isExternal: false
        )
    }
}
